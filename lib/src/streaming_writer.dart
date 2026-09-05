part of 'codec.dart';

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
  final int rowBytes;

  /// Creates a source over [bytes] without copying them.
  ///
  /// The caller must not mutate [bytes] until writing has completed.
  PsdMemoryPlanarSource({
    required this.bytes,
    required this.rowBytes,
  }) {
    if (rowBytes < 1 || bytes.lengthInBytes % rowBytes != 0) {
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

/// Locates one fixed-width length field for a later backpatch.
final class _PsdLengthPatch {
  /// Absolute output position of the field.
  final int offset;

  /// Whether the field occupies eight bytes instead of four.
  final bool wide;

  /// Creates a pending length field.
  const _PsdLengthPatch({required this.offset, required this.wide});
}

/// Locates one layer channel's length field and source.
final class _PsdChannelPatch {
  /// Pending encoded-byte length.
  final _PsdLengthPatch length;

  /// Channel samples and preferred compression.
  final PsdStreamChannel channel;

  /// Raster width represented by [channel].
  final int width;

  /// Raster height represented by [channel].
  final int height;

  /// Creates one pending channel payload.
  const _PsdChannelPatch({
    required this.length,
    required this.channel,
    required this.width,
    required this.height,
  });
}

/// Serializes a progressive model into one seekable output.
final class _PsdStreamingWriter {
  /// Destination receiving every encoded byte.
  final PsdRandomAccessOutput output;

  /// Container and compression overrides.
  final PsdWriteOptions options;

  /// Maximum rows requested from a source at once.
  final int rowBatchSize;

  /// Optional observer for expensive sample work.
  final PsdWriteProgress? onProgress;

  /// Total source rows expected for the current document.
  int _totalRows = 0;

  /// Source rows already consumed.
  int _completedRows = 0;

  /// Creates a bounded progressive writer.
  _PsdStreamingWriter({
    required this.output,
    required this.options,
    required this.rowBatchSize,
    required this.onProgress,
  }) {
    if (rowBatchSize < 1) {
      throw ArgumentError.value(
        rowBatchSize,
        'rowBatchSize',
        'must be positive',
      );
    }
  }

  /// Writes a complete document and returns its final byte length.
  Future<int> write(PsdStreamDocument source) async {
    final PsdDocument document = source.metadata;
    final PsdVersion version = options.version ?? document.version;
    _validateHeader(
      version: version,
      channels: document.channels,
      width: document.width,
      height: document.height,
      depth: document.depth,
      maxPixels: 0x7fffffffffffffff,
      writing: true,
    );
    if (source.mergedImage.length != document.channels) {
      throw PsWriteException(
        message:
            'Document declares ${document.channels} channels but provides '
            '${source.mergedImage.length} merged channel sources',
      );
    }
    if (source.layers.length > 0x7fff) {
      throw const PsWriteException(
        message: 'PSD supports at most 32767 layer records',
      );
    }
    _totalRows = document.height * source.mergedImage.length;
    for (final PsdStreamLayer layer in source.layers) {
      for (final PsdStreamChannel channel in layer.channels) {
        _totalRows += _channelRectangle(
          layer.metadata,
          channel.id,
        ).height;
      }
    }

    await output.truncate(0);
    await output.setPosition(0);
    await _writeHeader(document, version);
    await _writeColorModeData(document.colorModeData);
    await _writeResources(document.imageResources);
    await _writeLayerAndMask(source, version);
    await _writeMergedImage(source, version);
    final int length = output.position;
    await output.flush();
    return length;
  }

  /// Writes the fixed 26-byte file header.
  Future<void> _writeHeader(
    PsdDocument document,
    PsdVersion version,
  ) async {
    final PsBinaryWriter writer = PsBinaryWriter()
      ..writeString('8BPS')
      ..writeUint16(version.code)
      ..writeZeros(6)
      ..writeUint16(document.channels)
      ..writeUint32(document.height)
      ..writeUint32(document.width)
      ..writeUint16(document.depth)
      ..writeUint16(document.colorMode.code);
    await output.write(writer.takeBytes());
  }

  /// Writes colour-mode data without aggregating it with later sections.
  Future<void> _writeColorModeData(Uint8List bytes) async {
    await _writeUint32(bytes.lengthInBytes);
    await output.write(bytes);
  }

  /// Writes image resources and patches their aggregate 32-bit length.
  Future<void> _writeResources(List<PsdImageResource> resources) async {
    final _PsdLengthPatch section = await _reserveLength(wide: false);
    final int start = output.position;
    for (final PsdImageResource resource in resources) {
      _requireFourCharacters(
        resource.signature,
        'image-resource signature',
      );
      if (resource.id < 0 || resource.id > 0xffff) {
        throw PsWriteException(
          message: 'Image resource id ${resource.id} is outside 0...65535',
        );
      }
      final Uint8List name = _legacyName(resource.name);
      final PsBinaryWriter header = PsBinaryWriter()
        ..writeString(resource.signature)
        ..writeUint16(resource.id)
        ..writeUint8(name.length)
        ..writeBytes(name);
      if ((name.length + 1).isOdd) {
        header.writeUint8(0);
      }
      header.writeUint32(resource.data.lengthInBytes);
      await output.write(header.takeBytes());
      await output.write(resource.data);
      if (resource.data.lengthInBytes.isOdd) {
        await _writeUint8(0);
      }
    }
    await _patchLength(section, output.position - start);
  }

  /// Writes the layer-and-mask section with version-specific lengths.
  Future<void> _writeLayerAndMask(
    PsdStreamDocument source,
    PsdVersion version,
  ) async {
    final PsdDocument document = source.metadata;
    if (source.layers.isEmpty && document.globalLayerMaskData.isEmpty && document.additionalLayerInfo.isEmpty) {
      await _writeLength(0, wide: version == PsdVersion.psb);
      return;
    }
    final _PsdLengthPatch section = await _reserveLength(
      wide: version == PsdVersion.psb,
    );
    final int start = output.position;
    final PsdTaggedBlock? existingAlternative = _alternativeLayerInfo(
      document.additionalLayerInfo,
      document.depth,
    );
    final bool alternativeLayers = source.layers.isNotEmpty && (document.depth == 16 || document.depth == 32 || existingAlternative != null);
    if (alternativeLayers) {
      await _writeLength(0, wide: version == PsdVersion.psb);
    } else {
      await _writeLayerInfoSection(source, version);
    }
    await _writeUint32(document.globalLayerMaskData.lengthInBytes);
    await output.write(document.globalLayerMaskData);

    if (alternativeLayers) {
      final String key = switch (document.depth) {
        16 => 'Lr16',
        32 => 'Lr32',
        _ => 'Layr',
      };
      await _writeBlocksWithLayerInfo(
        source,
        document.additionalLayerInfo,
        version,
        key,
      );
    } else {
      final List<PsdTaggedBlock> blocks = existingAlternative != null && source.layers.isEmpty
          ? _removeAlternativeLayerInfo(
              document.additionalLayerInfo,
              existingAlternative.key,
            )
          : document.additionalLayerInfo;
      await _writeTaggedBlocksDirect(blocks, version);
    }
    await _patchLength(section, output.position - start);
  }

  /// Writes a length-prefixed ordinary layer-info payload.
  Future<void> _writeLayerInfoSection(
    PsdStreamDocument source,
    PsdVersion version,
  ) async {
    final _PsdLengthPatch length = await _reserveLength(
      wide: version == PsdVersion.psb,
    );
    final int start = output.position;
    await _writeLayerInfo(source, version);
    await _patchLength(length, output.position - start);
  }

  /// Replaces an existing alternate layer block or appends one.
  Future<void> _writeBlocksWithLayerInfo(
    PsdStreamDocument source,
    List<PsdTaggedBlock> blocks,
    PsdVersion version,
    String key,
  ) async {
    bool inserted = false;
    for (final PsdTaggedBlock block in blocks) {
      if (block.key == 'Layr' || block.key == 'Lr16' || block.key == 'Lr32') {
        if (!inserted) {
          await _writeLayerInfoBlock(
            source,
            version,
            signature: block.signature,
            key: key,
          );
          inserted = true;
        }
      } else {
        await _writeTaggedBlockDirect(block, version);
      }
    }
    if (!inserted) {
      await _writeLayerInfoBlock(
        source,
        version,
        signature: '8BIM',
        key: key,
      );
    }
  }

  /// Writes one alternate layer-info tagged block progressively.
  Future<void> _writeLayerInfoBlock(
    PsdStreamDocument source,
    PsdVersion version, {
    required String signature,
    required String key,
  }) async {
    _requireFourCharacters(signature, 'tagged-block signature');
    _requireFourCharacters(key, 'tagged-block key');
    await output.write(
      (PsBinaryWriter()
            ..writeString(signature)
            ..writeString(key))
          .takeBytes(),
    );
    final _PsdLengthPatch length = await _reserveLength(
      wide: version == PsdVersion.psb && _widePsbTaggedBlocks.contains(key),
    );
    final int start = output.position;
    await _writeLayerInfo(source, version);
    final int payloadLength = output.position - start;
    await _patchLength(length, payloadLength);
    if (payloadLength.isOdd) {
      await _writeUint8(0);
    }
  }

  /// Writes layer records first, then their channel payloads.
  Future<void> _writeLayerInfo(
    PsdStreamDocument source,
    PsdVersion version,
  ) async {
    if (source.layers.isEmpty) {
      return;
    }
    final int start = output.position;
    final int count = source.metadata.mergedTransparency ? -source.layers.length : source.layers.length;
    await _writeInt16(count);
    final List<_PsdChannelPatch> channels = [];
    for (final PsdStreamLayer streamed in source.layers) {
      final PsdLayer layer = streamed.metadata;
      final PsBinaryWriter record = PsBinaryWriter();
      _writeRectangle(record, layer.rectangle);
      record.writeUint16(streamed.channels.length);
      await output.write(record.takeBytes());
      for (final PsdStreamChannel channel in streamed.channels) {
        final PsdRectangle rectangle = _channelRectangle(layer, channel.id);
        await _writeInt16(channel.id);
        channels.add(
          _PsdChannelPatch(
            length: await _reserveLength(
              wide: version == PsdVersion.psb,
            ),
            channel: channel,
            width: rectangle.width,
            height: rectangle.height,
          ),
        );
      }
      _requireFourCharacters(layer.blendMode, 'blend mode');
      if (layer.opacity < 0 || layer.opacity > 255 || layer.clipping < 0 || layer.clipping > 255 || layer.flags < 0 || layer.flags > 255) {
        throw const PsWriteException(
          message: 'Layer opacity, clipping, and flags must fit in one byte',
        );
      }
      final Uint8List extra = _writeLayerExtra(layer, version);
      final PsBinaryWriter trailing = PsBinaryWriter()
        ..writeString('8BIM')
        ..writeString(layer.blendMode)
        ..writeUint8(layer.opacity)
        ..writeUint8(layer.clipping)
        ..writeUint8(layer.flags)
        ..writeUint8(0)
        ..writeUint32(extra.lengthInBytes)
        ..writeBytes(extra);
      await output.write(trailing.takeBytes());
    }
    for (final _PsdChannelPatch pending in channels) {
      final int channelStart = output.position;
      final PsdCompression compression = options.compression ?? pending.channel.compression;
      await _writeUint16(compression.code);
      await _writePlaneSources(
        [pending.channel.source],
        compression: compression,
        width: pending.width,
        height: pending.height,
        depth: source.metadata.depth,
        wideRowLengths: version == PsdVersion.psb,
      );
      await _patchLength(
        pending.length,
        output.position - channelStart,
      );
    }
    if ((output.position - start).isOdd) {
      await _writeUint8(0);
    }
  }

  /// Writes merged planes after their common compression marker.
  Future<void> _writeMergedImage(
    PsdStreamDocument source,
    PsdVersion version,
  ) async {
    final PsdCompression compression = options.compression ?? source.metadata.mergedImageCompression;
    await _writeUint16(compression.code);
    await _writePlaneSources(
      source.mergedImage,
      compression: compression,
      width: source.metadata.width,
      height: source.metadata.height,
      depth: source.metadata.depth,
      wideRowLengths: version == PsdVersion.psb,
    );
  }

  /// Writes one or more planes using bounded source reads.
  Future<void> _writePlaneSources(
    List<PsdPlanarSource> sources, {
    required PsdCompression compression,
    required int width,
    required int height,
    required int depth,
    required bool wideRowLengths,
  }) async {
    switch (compression) {
      case PsdCompression.raw:
        for (final PsdPlanarSource source in sources) {
          await _writeRawPlane(
            source,
            width: width,
            height: height,
            depth: depth,
          );
        }
      case PsdCompression.rle:
        await _writeRlePlanes(
          sources,
          width: width,
          height: height,
          depth: depth,
          wideRowLengths: wideRowLengths,
        );
      case PsdCompression.zip || PsdCompression.zipPrediction:
        throw const PsWriteException(
          message:
              'Progressive PSD writing supports RAW and RLE compression; '
              'use PsdCodec.encode for ZIP compression',
        );
    }
  }

  /// Copies a raw plane in bounded row batches.
  Future<void> _writeRawPlane(
    PsdPlanarSource source, {
    required int width,
    required int height,
    required int depth,
  }) async {
    final int rowBytes = psdRowBytes(width, depth);
    for (int startRow = 0; startRow < height;) {
      final int count = (height - startRow).clamp(1, rowBatchSize);
      final Uint8List rows = await source.readRows(
        startRow: startRow,
        rowCount: count,
      );
      _validateRows(rows, rowBytes: rowBytes, rowCount: count);
      await output.write(rows);
      startRow += count;
      _reportRows(count);
    }
  }

  /// Writes PackBits row bodies while backpatching bounded length batches.
  Future<void> _writeRlePlanes(
    List<PsdPlanarSource> sources, {
    required int width,
    required int height,
    required int depth,
    required bool wideRowLengths,
  }) async {
    final int rowBytes = psdRowBytes(width, depth);
    final int lengthBytes = wideRowLengths ? 4 : 2;
    final int rowCount = height * sources.length;
    final int tableOffset = output.position;
    await _writeZeros(rowCount * lengthBytes);
    const int lengthsPerBatch = 4096;
    final Uint32List lengths = Uint32List(lengthsPerBatch);
    int batchStartIndex = 0;
    int lengthIndex = 0;
    for (final PsdPlanarSource source in sources) {
      for (int startRow = 0; startRow < height;) {
        final int count = (height - startRow).clamp(1, rowBatchSize);
        final Uint8List rows = await source.readRows(
          startRow: startRow,
          rowCount: count,
        );
        _validateRows(rows, rowBytes: rowBytes, rowCount: count);
        for (int row = 0; row < count; row++) {
          final Uint8List encoded = encodePsdPackBitsRow(
            Uint8List.sublistView(
              rows,
              row * rowBytes,
              (row + 1) * rowBytes,
            ),
          );
          if (!wideRowLengths && encoded.lengthInBytes > 0xffff) {
            throw const PsWriteException(
              message:
                  'A PSD PackBits row exceeds 65535 encoded bytes; '
                  'use PSB or ZIP',
            );
          }
          lengths[lengthIndex - batchStartIndex] = encoded.lengthInBytes;
          lengthIndex++;
          await output.write(encoded);
          if (lengthIndex - batchStartIndex == lengths.length) {
            await _patchRleRowLengths(
              tableOffset,
              batchStartIndex,
              lengths,
              lengths.length,
              lengthBytes,
            );
            batchStartIndex = lengthIndex;
          }
        }
        startRow += count;
        _reportRows(count);
      }
    }
    final int remaining = lengthIndex - batchStartIndex;
    if (remaining > 0) {
      await _patchRleRowLengths(
        tableOffset,
        batchStartIndex,
        lengths,
        remaining,
        lengthBytes,
      );
    }
  }

  /// Backpatches [count] row lengths without losing the append position.
  Future<void> _patchRleRowLengths(
    int tableOffset,
    int startIndex,
    Uint32List lengths,
    int count,
    int lengthBytes,
  ) async {
    final int end = output.position;
    await output.setPosition(tableOffset + startIndex * lengthBytes);
    final Uint8List bytes = Uint8List(count * lengthBytes);
    final ByteData values = ByteData.sublistView(bytes);
    for (int index = 0; index < count; index++) {
      final int value = lengths[index];
      if (lengthBytes == 4) {
        values.setUint32(index * 4, value);
      } else {
        values.setUint16(index * 2, value);
      }
    }
    await output.write(bytes);
    await output.setPosition(end);
  }

  /// Verifies that one source fulfilled its exact row contract.
  void _validateRows(
    Uint8List rows, {
    required int rowBytes,
    required int rowCount,
  }) {
    final int expected = rowBytes * rowCount;
    if (rows.lengthInBytes != expected) {
      throw PsWriteException(
        message:
            'Planar source returned ${rows.lengthInBytes} bytes; '
            '$rowCount rows require $expected',
      );
    }
  }

  /// Notifies the progress observer after source rows are consumed.
  void _reportRows(int count) {
    _completedRows += count;
    onProgress?.call(_completedRows, _totalRows);
  }

  /// Writes ordinary tagged blocks without joining their payloads.
  Future<void> _writeTaggedBlocksDirect(
    List<PsdTaggedBlock> blocks,
    PsdVersion version,
  ) async {
    for (final PsdTaggedBlock block in blocks) {
      await _writeTaggedBlockDirect(block, version);
    }
  }

  /// Writes one ordinary tagged block and its even-byte padding.
  Future<void> _writeTaggedBlockDirect(
    PsdTaggedBlock block,
    PsdVersion version,
  ) async {
    _requireFourCharacters(block.signature, 'tagged-block signature');
    _requireFourCharacters(block.key, 'tagged-block key');
    final bool wide = version == PsdVersion.psb && _widePsbTaggedBlocks.contains(block.key);
    final PsBinaryWriter header = PsBinaryWriter()
      ..writeString(block.signature)
      ..writeString(block.key)
      ..writeLength(block.data.lengthInBytes, wide: wide);
    await output.write(header.takeBytes());
    await output.write(block.data);
    if (block.data.lengthInBytes.isOdd) {
      await _writeUint8(0);
    }
  }

  /// Reserves a zero length field at the current position.
  Future<_PsdLengthPatch> _reserveLength({required bool wide}) async {
    final _PsdLengthPatch patch = _PsdLengthPatch(
      offset: output.position,
      wide: wide,
    );
    await _writeLength(0, wide: wide);
    return patch;
  }

  /// Rewrites [patch] while preserving the current append position.
  Future<void> _patchLength(_PsdLengthPatch patch, int value) async {
    final int end = output.position;
    await output.setPosition(patch.offset);
    await _writeLength(value, wide: patch.wide);
    await output.setPosition(end);
  }

  /// Writes a version-dependent unsigned section length.
  Future<void> _writeLength(int value, {required bool wide}) async {
    final PsBinaryWriter writer = PsBinaryWriter()..writeLength(value, wide: wide);
    await output.write(writer.takeBytes());
  }

  /// Writes one signed 16-bit integer.
  Future<void> _writeInt16(int value) async {
    final PsBinaryWriter writer = PsBinaryWriter()..writeInt16(value);
    await output.write(writer.takeBytes());
  }

  /// Writes one unsigned 8-bit integer.
  Future<void> _writeUint8(int value) async {
    final PsBinaryWriter writer = PsBinaryWriter()..writeUint8(value);
    await output.write(writer.takeBytes());
  }

  /// Writes one unsigned 16-bit integer.
  Future<void> _writeUint16(int value) async {
    final PsBinaryWriter writer = PsBinaryWriter()..writeUint16(value);
    await output.write(writer.takeBytes());
  }

  /// Writes one unsigned 32-bit integer.
  Future<void> _writeUint32(int value) async {
    final PsBinaryWriter writer = PsBinaryWriter()..writeUint32(value);
    await output.write(writer.takeBytes());
  }

  /// Writes [count] zero bytes without allocating one giant placeholder.
  Future<void> _writeZeros(int count) async {
    const int batchSize = 64 * 1024;
    final Uint8List batch = Uint8List(batchSize);
    int remaining = count;
    while (remaining > 0) {
      final int written = remaining.clamp(1, batchSize);
      await output.write(
        written == batchSize ? batch : Uint8List.sublistView(batch, 0, written),
      );
      remaining -= written;
    }
  }
}
