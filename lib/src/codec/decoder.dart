part of '../codec.dart';

/// Collects decoded values from the layer-and-mask section.
final class _LayerSection {
  /// Decoded flat layer records.
  final List<PsdLayer> layers;

  /// Whether the signed layer count advertises merged transparency.
  final bool mergedTransparency;

  /// Uninterpreted global layer-mask payload.
  final Uint8List globalMask;

  /// Tagged blocks stored after the global layer mask.
  final List<PsdTaggedBlock> additionalInfo;

  /// Groups the independently decoded layer-and-mask subsections.
  const _LayerSection({
    required this.layers,
    required this.mergedTransparency,
    required this.globalMask,
    required this.additionalInfo,
  });
}

/// Collects records and transparency state from one layer-info payload.
final class _DecodedLayerInfo {
  /// Decoded flat layer records.
  final List<PsdLayer> layers;

  /// Whether the signed layer count advertises merged transparency.
  final bool mergedTransparency;

  /// Creates decoded layer-info state.
  const _DecodedLayerInfo({required this.layers, required this.mergedTransparency});
}

/// Holds a layer record until its channel payloads can be decoded.
final class _LayerRecord {
  /// Layer metadata and placeholder channel ids.
  final PsdLayer layer;

  /// Encoded byte length for each placeholder channel.
  final List<int> channelLengths;

  /// Creates a pending record from its metadata and channel lengths.
  const _LayerRecord({required this.layer, required this.channelLengths});
}

/// Reads every bounded Photoshop image-resource block.
List<PsdImageResource> _readImageResources(PsBinaryReader reader) {
  final List<PsdImageResource> result = <PsdImageResource>[];
  while (!reader.isAtEnd) {
    if (reader.remaining < 12) {
      throw PsFormatException(message: 'Truncated image resource block', source: reader.bytes, offset: reader.baseOffset + reader.offset);
    }
    final String signature = reader.readString(4);
    final int id = reader.readUint16();
    final int nameLength = reader.readUint8();
    final String name = reader.readString(nameLength);
    if ((nameLength + 1).isOdd) {
      reader.skip(1);
    }
    final int dataLength = reader.readUint32();
    final Uint8List data = reader.readBytes(dataLength);
    if (dataLength.isOdd) {
      reader.skip(1);
    }
    result.add(PsdImageResource(id: id, name: name, signature: signature, data: data));
  }
  return result;
}

/// Reads layer records, global mask bytes, and trailing tagged blocks.
_LayerSection _readLayerAndMask(PsBinaryReader reader, {required PsdVersion version, required int depth, required PsdReadOptions options}) {
  if (reader.isAtEnd) {
    return _LayerSection(layers: const <PsdLayer>[], mergedTransparency: false, globalMask: Uint8List(0), additionalInfo: const <PsdTaggedBlock>[]);
  }
  final int layerInfoLength = reader.readLength(wide: version == PsdVersion.psb, label: 'layer info');
  _DecodedLayerInfo decoded = _readLayerInfo(reader.readReader(layerInfoLength), version: version, depth: depth, options: options);

  Uint8List globalMask = Uint8List(0);
  if (reader.remaining >= 4) {
    final int length = reader.readLength(wide: false, label: 'global layer mask');
    globalMask = reader.readBytes(length);
  }
  final List<PsdTaggedBlock> additionalInfo = _readTaggedBlocks(reader, version);
  final PsdTaggedBlock? alternative = _alternativeLayerInfo(additionalInfo, depth);
  if (alternative != null) {
    decoded = _readLayerInfo(
      PsBinaryReader(bytes: alternative.data),
      version: version,
      depth: depth,
      options: options,
    );
  }
  return _LayerSection(
    layers: decoded.layers,
    mergedTransparency: decoded.mergedTransparency,
    globalMask: globalMask,
    additionalInfo: additionalInfo,
  );
}

/// Reads records and channel payloads from one primary or alternative layer info.
_DecodedLayerInfo _readLayerInfo(PsBinaryReader layerInfo, {required PsdVersion version, required int depth, required PsdReadOptions options}) {
  bool mergedTransparency = false;
  final List<PsdLayer> layers = <PsdLayer>[];
  if (!layerInfo.isAtEnd) {
    final int signedCount = layerInfo.readInt16();
    mergedTransparency = signedCount < 0;
    final int count = signedCount.abs();
    if (count > options.maxLayers) {
      throw PsFormatException(message: 'Layer count $count exceeds the configured limit');
    }
    final List<_LayerRecord> records = <_LayerRecord>[];
    for (int index = 0; index < count; index++) {
      records.add(_readLayerRecord(layerInfo, version));
    }
    for (final _LayerRecord record in records) {
      final List<PsdChannel> channels = <PsdChannel>[];
      for (int index = 0; index < record.channelLengths.length; index++) {
        final PsdChannel descriptor = record.layer.channels[index];
        final int encodedLength = record.channelLengths[index];
        if (encodedLength < 2) {
          throw const PsFormatException(message: 'Layer channel length is smaller than its compression marker');
        }
        final PsBinaryReader encoded = layerInfo.readReader(encodedLength);
        final PsdCompression compression = _enumByCode(PsdCompression.values, encoded.readUint16(), 'layer channel compression', encoded);
        final PsdRectangle rectangle = _channelRectangle(record.layer, descriptor.id);
        final Uint8List payload = encoded.readView(encoded.remaining);
        final Uint8List decoded = decodePsdChannel(
          compression: compression,
          payload: payload,
          width: rectangle.width,
          height: rectangle.height,
          depth: depth,
          wideRowLengths: version == PsdVersion.psb,
          maxDecodedBytes: options.maxDecodedBytes,
        );
        if (options.preserveSourceEncoding) {
          _SourceEncoding.remember([decoded], geometry: (rectangle.width, rectangle.height, depth, false), compression: compression, payload: payload, wideRowLengths: version == PsdVersion.psb);
        }
        channels.add(PsdChannel(id: descriptor.id, data: decoded, compression: compression));
      }
      layers.add(copyPsdLayer(record.layer, channels: channels));
    }
    if (!layerInfo.isAtEnd) {
      final int trailingOffset = layerInfo.offset;
      final Uint8List trailing = layerInfo.readBytes(layerInfo.remaining);
      if (trailing.any((value) => value != 0)) {
        final String prefix = trailing.take(16).map((value) => value.toRadixString(16).padLeft(2, '0')).join(' ');
        throw PsFormatException(message: 'Unexpected ${trailing.length} bytes at the end of layer info: $prefix', source: layerInfo.bytes, offset: layerInfo.baseOffset + trailingOffset);
      }
      // Some writers align layer info to four bytes rather than two.
      _layerInfoPadding[layers] = trailing.length;
    }
  }
  return _DecodedLayerInfo(layers: layers, mergedTransparency: mergedTransparency);
}

/// Selects the depth-specific layer-info block, when Photoshop stored one.
PsdTaggedBlock? _alternativeLayerInfo(List<PsdTaggedBlock> blocks, int depth) {
  final String key = _alternativeLayerInfoKey(depth);
  for (final PsdTaggedBlock block in blocks.reversed) {
    if (block.key == key) {
      return block;
    }
  }
  return null;
}

/// Reads one layer record without consuming its later channel payloads.
_LayerRecord _readLayerRecord(PsBinaryReader reader, PsdVersion version) {
  final PsdRectangle rectangle = _readRectangle(reader);
  final int channelCount = reader.readUint16();
  final List<PsdChannel> channelDescriptors = <PsdChannel>[];
  final List<int> channelLengths = <int>[];
  for (int channel = 0; channel < channelCount; channel++) {
    channelDescriptors.add(PsdChannel(id: reader.readInt16(), data: Uint8List(0)));
    channelLengths.add(version == PsdVersion.psb ? reader.readUint64() : reader.readUint32());
  }
  if (reader.readString(4) != '8BIM') {
    throw PsFormatException(message: 'Invalid layer blend-mode signature', source: reader.bytes, offset: reader.baseOffset + reader.offset - 4);
  }
  final String blendMode = reader.readString(4);
  final int opacity = reader.readUint8();
  final int clipping = reader.readUint8();
  final int flags = reader.readUint8();
  reader.skip(1);
  final PsBinaryReader extra = reader.readReader(reader.readLength(wide: false, label: 'layer extra data'));
  final int maskLength = extra.readLength(wide: false, label: 'layer mask data');
  final PsdLayerMask? mask = maskLength == 0 ? null : _readMask(extra.readBytes(maskLength), hasRealMask: channelDescriptors.any((channel) => channel.id == -3));
  final Uint8List blendingRanges = extra.readBytes(extra.readLength(wide: false, label: 'layer blending ranges'));
  final int nameStart = extra.offset;
  final int nameLength = extra.readUint8();
  final String pascalName = extra.readString(nameLength);
  final int nameBytes = extra.offset - nameStart;
  final int padding = (4 - nameBytes % 4) % 4;
  extra.skip(padding);
  final List<PsdTaggedBlock> additionalInfo = _readTaggedBlocks(extra, version);
  final String name = _unicodeLayerName(additionalInfo) ?? pascalName;
  return _LayerRecord(
    layer: PsdLayer(
      rectangle: rectangle,
      name: name,
      channels: channelDescriptors,
      blendMode: blendMode,
      opacity: opacity,
      clipping: clipping,
      flags: flags,
      mask: mask,
      blendingRanges: blendingRanges,
      additionalInfo: additionalInfo,
      writesUnicodeName: additionalInfo.any((block) => block.key == 'luni'),
    ),
    channelLengths: channelLengths,
  );
}

/// Parses stable fields from a layer-mask payload while retaining all bytes.
PsdLayerMask _readMask(Uint8List data, {required bool hasRealMask}) {
  if (data.length < 18) {
    throw const PsFormatException(message: 'Layer mask data is shorter than 18 bytes');
  }
  final PsBinaryReader reader = PsBinaryReader(bytes: data);
  final PsdRectangle rectangle = _readRectangle(reader);
  final int defaultColor = reader.readUint8();
  final int flags = reader.readUint8();
  PsdRectangle? realRectangle;
  int? realFlags;
  int? realDefaultColor;
  if (hasRealMask) {
    // Photoshop stores the real-mask header before the optional parameters.
    // Parameters alone can also make a block exceed 36 bytes, so its length
    // does not establish the presence of this header; channel -3 does.
    realFlags = reader.readUint8();
    realDefaultColor = reader.readUint8();
    realRectangle = _readRectangle(reader);
  }
  return PsdLayerMask(
    rectangle: rectangle,
    defaultColor: defaultColor,
    flags: flags,
    realRectangle: realRectangle,
    realFlags: realFlags,
    realDefaultColor: realDefaultColor,
    data: data,
  );
}
