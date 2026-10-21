part of '../codec.dart';

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

  /// Encodes pixel planes while this writer owns section order and progress.
  late final _PsdPlaneWriter _planes = _PsdPlaneWriter(
    output: output,
    rowBatchSize: rowBatchSize,
    onRows: _reportRows,
  );

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
    _rejectForeignTiffBlocks(source.metadata, layers: source.layers.map((layer) => layer.metadata));
    final PsdDocument document = source.metadata;
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
    await _writeColorModeData(_outputColorModeData(document, options));
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
    final PsBinaryWriter writer = PsBinaryWriter();
    _writeDocumentHeader(writer, document, version);
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
      final PsBinaryWriter header = PsBinaryWriter();
      _writeImageResourceHeader(header, resource);
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
    final _PsdLayerInfoLayout layout = _layerInfoLayout(
      depth: document.depth,
      hasLayers: source.layers.isNotEmpty,
      blocks: document.additionalLayerInfo,
    );
    if (layout.alternativeKey != null) {
      await _writeLength(0, wide: version == PsdVersion.psb);
    } else {
      await _writeLayerInfoSection(source, version);
    }
    await _writeUint32(document.globalLayerMaskData.lengthInBytes);
    await output.write(document.globalLayerMaskData);
    for (final PsdTaggedBlock block in layout.blocks) {
      if (block.key == layout.alternativeKey) {
        await _writeLayerInfoBlock(source, version, signature: block.signature, key: block.key);
      } else {
        await _writeTaggedBlockDirect(block, version);
      }
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
      final PsBinaryWriter trailing = PsBinaryWriter();
      _writeLayerRecordMetadata(trailing, layer, version);
      await output.write(trailing.takeBytes());
    }
    for (final _PsdChannelPatch pending in channels) {
      final int channelStart = output.position;
      final PsdCompression compression = _outputCompression(pending.channel.compression, source.metadata.depth, options);
      await _writeUint16(compression.code);
      await _planes.write(
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
    final PsdCompression compression = _outputCompression(source.metadata.mergedImageCompression, source.metadata.depth, options);
    await _writeUint16(compression.code);
    await _planes.write(
      source.mergedImage,
      compression: compression,
      width: source.metadata.width,
      height: source.metadata.height,
      depth: source.metadata.depth,
      wideRowLengths: version == PsdVersion.psb,
    );
  }

  /// Notifies the progress observer after source rows are consumed.
  void _reportRows(int count) {
    _completedRows += count;
    onProgress?.call(_completedRows, _totalRows);
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
}
