import 'dart:convert';
import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:psdkit/src/compression.dart';
import 'package:psdkit/src/model.dart';
import 'package:psdkit/src/model/copy.dart';

part 'codec/binary_io.dart';
part 'codec/decoder.dart';
part 'codec/encoder.dart';
part 'codec/layer_info_layout.dart';
part 'codec/metadata_writer.dart';
part 'codec/plane_writer.dart';
part 'codec/source_encoding.dart';
part 'codec/streaming_encoder.dart';
part 'codec/streaming_model.dart';
part 'codec/tagged_blocks.dart';

/// Reads and writes complete PSD and PSB byte streams.
abstract final class PsdCodec {
  /// Decodes [bytes] into an editable, loss-preserving document model.
  static PsdDocument decode(Uint8List bytes, {PsdReadOptions options = const PsdReadOptions()}) {
    final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
    if (reader.readString(4) != '8BPS') {
      throw PsFormatException(message: 'Invalid file signature', source: bytes, offset: 0);
    }
    final int versionCode = reader.readUint16();
    final PsdVersion version = _enumByCode(PsdVersion.values, versionCode, 'PSD version', reader);
    if (reader.readBytes(6).any((value) => value != 0)) {
      throw PsFormatException(message: 'Reserved header bytes must be zero', source: bytes, offset: 6);
    }
    final int channelCount = reader.readUint16();
    final int height = reader.readUint32();
    final int width = reader.readUint32();
    final int depth = reader.readUint16();
    final PsdColorMode colorMode = _enumByCode(PsdColorMode.values, reader.readUint16(), 'color mode', reader);
    _validateHeader(version: version, channels: channelCount, width: width, height: height, depth: depth, maxPixels: options.maxPixels, writing: false);

    final Uint8List colorModeData = reader.readBytes(reader.readLength(wide: false, label: 'color mode data'));
    final List<PsdImageResource> resources = _readImageResources(reader.readReader(reader.readLength(wide: false, label: 'image resources')));
    final _LayerSection layerSection = _readLayerAndMask(
      reader.readReader(reader.readLength(wide: version == PsdVersion.psb, label: 'layer and mask information')),
      version: version,
      depth: depth,
      options: options,
    );

    if (reader.remaining < 2) {
      throw PsFormatException(message: 'Missing merged image data', source: bytes, offset: reader.offset);
    }
    final PsdCompression mergedCompression = _enumByCode(PsdCompression.values, reader.readUint16(), 'merged image compression', reader);
    final Uint8List mergedPayload = reader.readView(reader.remaining);
    final List<Uint8List> mergedImage = decodePsdMergedImage(
      compression: mergedCompression,
      payload: mergedPayload,
      channels: channelCount,
      width: width,
      height: height,
      depth: depth,
      wideRowLengths: version == PsdVersion.psb,
      maxDecodedBytes: options.maxDecodedBytes,
    );
    if (options.preserveSourceEncoding) {
      _SourceEncoding.remember(mergedImage, geometry: (width, height, depth, true), compression: mergedCompression, payload: mergedPayload, wideRowLengths: version == PsdVersion.psb);
    }
    return PsdDocument(
      version: version,
      width: width,
      height: height,
      channels: channelCount,
      depth: depth,
      colorMode: colorMode,
      colorModeData: colorModeData,
      imageResources: resources,
      layers: layerSection.layers,
      mergedImage: mergedImage,
      mergedImageCompression: mergedCompression,
      mergedTransparency: layerSection.mergedTransparency,
      globalLayerMaskData: layerSection.globalMask,
      additionalLayerInfo: layerSection.additionalInfo,
    );
  }

  /// Encodes [document] into a complete PSD or PSB file.
  static Uint8List encode(PsdDocument document, {PsdWriteOptions options = const PsdWriteOptions()}) {
    final PsdVersion version = options.version ?? document.version;
    _validateHeader(
      version: version,
      channels: document.channels,
      width: document.width,
      height: document.height,
      depth: document.depth,
      maxPixels: _maximumWritablePixels,
      writing: true,
    );
    if (document.mergedImage.length != document.channels) {
      throw PsWriteException(message: 'Document declares ${document.channels} channels but provides ${document.mergedImage.length} merged channels');
    }
    final PsBinaryWriter writer = PsBinaryWriter();
    _writeDocumentHeader(writer, document, version);
    writer
      ..writeUint32(document.colorModeData.length)
      ..writeBytes(document.colorModeData);

    final Uint8List resources = _writeImageResources(document.imageResources);
    writer
      ..writeUint32(resources.length)
      ..writeBytes(resources);
    final Uint8List layerAndMask = _writeLayerAndMask(document, version: version, compressionOverride: options.compression);
    writer
      ..writeLength(layerAndMask.length, wide: version == PsdVersion.psb)
      ..writeBytes(layerAndMask);

    final PsdCompression mergedCompression = options.compression ?? document.mergedImageCompression;
    final Uint8List imageData =
        _SourceEncoding.reuse(document.mergedImage, geometry: (document.width, document.height, document.depth, true), compression: mergedCompression, wideRowLengths: version == PsdVersion.psb) ??
        encodePsdMergedImage(
          compression: mergedCompression,
          channels: document.mergedImage,
          width: document.width,
          height: document.height,
          depth: document.depth,
          wideRowLengths: version == PsdVersion.psb,
        );
    writer
      ..writeUint16(mergedCompression.code)
      ..writeBytes(imageData);
    return writer.takeBytes();
  }

  /// Writes [document] progressively to a seekable [output].
  ///
  /// Only bounded row batches and metadata blocks are retained while pixels
  /// are written. Raw and PackBits compression are supported because their
  /// rows can be emitted independently; use [encode] when ZIP compression is
  /// required. The returned value is the final byte length.
  static Future<int> encodeTo(
    PsdStreamDocument document,
    PsdRandomAccessOutput output, {
    PsdWriteOptions options = const PsdWriteOptions(),
    int rowBatchSize = 64,
    PsdWriteProgress? onProgress,
  }) => _PsdStreamingWriter(
    output: output,
    options: options,
    rowBatchSize: rowBatchSize,
    onProgress: onProgress,
  ).write(document);
}

/// Converts complete PSD and PSB documents through the `dart:convert` API.
///
/// The byte representation uses [List<int>] so this codec can be fused with
/// standard Dart codecs such as `base64`. [encode] returns a [Uint8List], and
/// [decode] avoids copying inputs that are already [Uint8List] instances.
///
/// Both conversions retain a complete document in memory. Use
/// [PsdCodec.encodeTo] for bounded-memory RAW or PackBits output.
final class PsdDocumentCodec extends Codec<PsdDocument, List<int>> {
  /// Limits applied while decoding documents.
  final PsdReadOptions readOptions;

  /// Defaults applied while encoding documents.
  final PsdWriteOptions writeOptions;

  /// Creates a codec with the requested read and write behavior.
  const PsdDocumentCodec({
    this.readOptions = const PsdReadOptions(),
    this.writeOptions = const PsdWriteOptions(),
  });

  @override
  Converter<PsdDocument, List<int>> get encoder => _PsdDocumentEncoder(options: writeOptions);

  @override
  Converter<List<int>, PsdDocument> get decoder => _PsdDocumentDecoder(options: readOptions);

  @override
  Uint8List encode(PsdDocument input) => PsdCodec.encode(input, options: writeOptions);

  @override
  PsdDocument decode(List<int> encoded) => PsdCodec.decode(_asUint8List(encoded), options: readOptions);
}

/// Converts complete PSD and PSB documents with the default options.
const PsdDocumentCodec psdDocumentCodec = PsdDocumentCodec();

/// Adapts the PSD writer to the `dart:convert` converter contract.
final class _PsdDocumentEncoder extends Converter<PsdDocument, List<int>> {
  /// Options forwarded to the PSD writer.
  final PsdWriteOptions options;

  /// Creates an encoder using [options].
  const _PsdDocumentEncoder({required this.options});

  @override
  Uint8List convert(PsdDocument input) => PsdCodec.encode(input, options: options);
}

/// Adapts the PSD reader to the `dart:convert` converter contract.
final class _PsdDocumentDecoder extends Converter<List<int>, PsdDocument> {
  /// Limits forwarded to the PSD reader.
  final PsdReadOptions options;

  /// Creates a decoder using [options].
  const _PsdDocumentDecoder({required this.options});

  @override
  PsdDocument convert(List<int> input) => PsdCodec.decode(_asUint8List(input), options: options);
}

/// Returns [bytes] as typed bytes without copying an existing [Uint8List].
Uint8List _asUint8List(List<int> bytes) {
  if (bytes is Uint8List) {
    return bytes;
  }
  for (final int byte in bytes) {
    RangeError.checkValueInInterval(byte, 0, 255, 'bytes');
  }
  return Uint8List.fromList(bytes);
}
