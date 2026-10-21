part of '../codec.dart';

/// Receives PSD bytes while allowing earlier length fields to be patched.
///
/// Implementations own their underlying file or buffer. [PsdCodec.encodeTo]
/// flushes but does not close the output.
abstract interface class PsdRandomAccessOutput {
  /// Current zero-based byte position.
  int get position;

  /// Discards existing output and sets its length to [length].
  Future<void> truncate(int length);

  /// Moves the next write to [position].
  Future<void> setPosition(int position);

  /// Writes every byte in [bytes] at the current position.
  Future<void> write(Uint8List bytes);

  /// Makes every completed write durable according to the backing store.
  Future<void> flush();
}

/// Supplies uncompressed big-endian samples for one planar channel.
abstract interface class PsdPlanarSource {
  /// Reads [rowCount] complete rows beginning at [startRow].
  ///
  /// The returned bytes must contain exactly the requested rows in row-major
  /// order. A writer never overlaps requests and consumes rows in ascending
  /// order, but sources may support arbitrary reads when convenient.
  Future<Uint8List> readRows({
    required int startRow,
    required int rowCount,
  });
}

/// Adapts an in-memory plane to the progressive writer.
final class PsdMemoryPlanarSource implements PsdPlanarSource {
  /// Complete row-major plane supplied by the caller.
  final Uint8List bytes;

  /// Stored bytes in one row.
  ///
  /// Zero is valid for the empty planes of a group divider or of any layer
  /// whose rectangle has no width; [bytes] must then be empty as well.
  final int rowBytes;

  /// Creates a source over [bytes] without copying them.
  ///
  /// The caller must not mutate [bytes] until writing has completed.
  PsdMemoryPlanarSource({
    required this.bytes,
    required this.rowBytes,
  }) {
    final bool divides = rowBytes == 0 ? bytes.lengthInBytes == 0 : bytes.lengthInBytes % rowBytes == 0;
    if (rowBytes < 0 || !divides) {
      throw ArgumentError.value(
        rowBytes,
        'rowBytes',
        'must divide the plane byte length exactly',
      );
    }
  }

  @override
  Future<Uint8List> readRows({
    required int startRow,
    required int rowCount,
  }) async {
    final int start = startRow * rowBytes;
    final int end = start + rowCount * rowBytes;
    if (startRow < 0 || rowCount < 1 || end > bytes.lengthInBytes) {
      throw RangeError.range(
        end,
        0,
        bytes.lengthInBytes,
        'requested rows',
      );
    }
    return Uint8List.sublistView(bytes, start, end);
  }
}

/// Associates a layer channel identifier with progressive sample storage.
final class PsdStreamChannel {
  /// Component id, where `-1` is transparency and `-2` is the user mask.
  final int id;

  /// Uncompressed samples read by the writer.
  final PsdPlanarSource source;

  /// Preferred encoding when no global override is supplied.
  final PsdCompression compression;

  /// Creates one progressively writable layer channel.
  const PsdStreamChannel({
    required this.id,
    required this.source,
    this.compression = PsdCompression.rle,
  });
}

/// Combines layer metadata with independently supplied channel samples.
final class PsdStreamLayer {
  /// Layer record metadata and tagged blocks.
  ///
  /// [PsdLayer.channels] is ignored; [channels] is authoritative.
  final PsdLayer metadata;

  /// Channels written after all layer records.
  final List<PsdStreamChannel> channels;

  /// Creates one progressively writable layer.
  const PsdStreamLayer({
    required this.metadata,
    required this.channels,
  });
}

/// Describes a PSD or PSB whose pixel planes can be read incrementally.
final class PsdStreamDocument {
  /// Document header, resources, global mask, and tagged-block metadata.
  ///
  /// [PsdDocument.layers] and [PsdDocument.mergedImage] are ignored; [layers]
  /// and [mergedImage] are authoritative.
  final PsdDocument metadata;

  /// Flat layer-record order with progressive channel sources.
  final List<PsdStreamLayer> layers;

  /// Merged-image planes in file order.
  final List<PsdPlanarSource> mergedImage;

  /// Creates a progressively writable document.
  const PsdStreamDocument({
    required this.metadata,
    required this.layers,
    required this.mergedImage,
  });

  /// Wraps every plane in [document] without copying its samples.
  factory PsdStreamDocument.fromDocument(PsdDocument document) {
    final int mergedRowBytes = psdRowBytes(
      document.width,
      document.depth,
    );
    return PsdStreamDocument(
      metadata: document,
      layers: [
        for (final PsdLayer layer in document.layers)
          PsdStreamLayer(
            metadata: layer,
            channels: [
              for (final PsdChannel channel in layer.channels)
                PsdStreamChannel(
                  id: channel.id,
                  source: PsdMemoryPlanarSource(
                    bytes: channel.data,
                    rowBytes: psdRowBytes(
                      _channelRectangle(layer, channel.id).width,
                      document.depth,
                    ),
                  ),
                  compression: channel.compression,
                ),
            ],
          ),
      ],
      mergedImage: [
        for (final Uint8List channel in document.mergedImage)
          PsdMemoryPlanarSource(
            bytes: channel,
            rowBytes: mergedRowBytes,
          ),
      ],
    );
  }
}

/// Reports completed and total source rows during progressive encoding.
typedef PsdWriteProgress = void Function(int completedRows, int totalRows);
