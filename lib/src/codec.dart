import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:psdkit/src/compression.dart';
import 'package:psdkit/src/model.dart';

part 'streaming_writer.dart';

/// Tagged blocks whose payload length expands to 64 bits in PSB files.
const Set<String> _widePsbTaggedBlocks = <String>{
  'LMsk',
  'Lr16',
  'Lr32',
  'Layr',
  'Mt16',
  'Mt32',
  'Mtrn',
  'Alph',
  'FMsk',
  'lnk2',
  'FEid',
  'FXid',
  'PxSD',
};

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
    final List<Uint8List> mergedImage = decodePsdMergedImage(
      compression: mergedCompression,
      payload: reader.readView(reader.remaining),
      channels: channelCount,
      width: width,
      height: height,
      depth: depth,
      wideRowLengths: version == PsdVersion.psb,
      maxDecodedBytes: options.maxDecodedBytes,
    );
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
      maxPixels: 0x7fffffffffffffff,
      writing: true,
    );
    if (document.mergedImage.length != document.channels) {
      throw PsWriteException(message: 'Document declares ${document.channels} channels but provides ${document.mergedImage.length} merged channels');
    }
    final PsBinaryWriter writer = PsBinaryWriter()
      ..writeString('8BPS')
      ..writeUint16(version.code)
      ..writeZeros(6)
      ..writeUint16(document.channels)
      ..writeUint32(document.height)
      ..writeUint32(document.width)
      ..writeUint16(document.depth)
      ..writeUint16(document.colorMode.code)
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
    final Uint8List imageData = encodePsdMergedImage(
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

/// Holds a layer and its encoded channel payloads during writing.
final class _EncodedLayer {
  /// Layer metadata to serialize.
  final PsdLayer layer;

  /// Complete channel payloads, including compression markers.
  final List<Uint8List> channels;

  /// Creates a serialized-channel staging value.
  const _EncodedLayer({required this.layer, required this.channels});
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
        final Uint8List decoded = decodePsdChannel(
          compression: compression,
          payload: encoded.readView(encoded.remaining),
          width: rectangle.width,
          height: rectangle.height,
          depth: depth,
          wideRowLengths: version == PsdVersion.psb,
          maxDecodedBytes: options.maxDecodedBytes,
        );
        channels.add(PsdChannel(id: descriptor.id, data: decoded, compression: compression));
      }
      layers.add(_copyLayer(record.layer, channels));
    }
    if (!layerInfo.isAtEnd) {
      final int trailingOffset = layerInfo.offset;
      final Uint8List trailing = layerInfo.readBytes(layerInfo.remaining);
      if (trailing.any((value) => value != 0)) {
        final String prefix = trailing.take(16).map((value) => value.toRadixString(16).padLeft(2, '0')).join(' ');
        throw PsFormatException(message: 'Unexpected ${trailing.length} bytes at the end of layer info: $prefix', source: layerInfo.bytes, offset: layerInfo.baseOffset + trailingOffset);
      }
    }
  }
  return _DecodedLayerInfo(layers: layers, mergedTransparency: mergedTransparency);
}

/// Selects the depth-specific layer-info block, when Photoshop stored one.
PsdTaggedBlock? _alternativeLayerInfo(List<PsdTaggedBlock> blocks, int depth) {
  final String key = switch (depth) {
    16 => 'Lr16',
    32 => 'Lr32',
    _ => 'Layr',
  };
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
  final PsdLayerMask? mask = maskLength == 0 ? null : _readMask(extra.readBytes(maskLength));
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
    ),
    channelLengths: channelLengths,
  );
}

/// Parses stable fields from a layer-mask payload while retaining all bytes.
PsdLayerMask _readMask(Uint8List data) {
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
  if (data.length >= 36) {
    final PsBinaryReader tail = PsBinaryReader(bytes: Uint8List.sublistView(data, data.length - 18));
    realFlags = tail.readUint8();
    realDefaultColor = tail.readUint8();
    realRectangle = _readRectangle(tail);
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

/// Reads aligned additional-layer-information blocks to the bounded end.
List<PsdTaggedBlock> _readTaggedBlocks(PsBinaryReader reader, PsdVersion version) {
  final List<PsdTaggedBlock> result = <PsdTaggedBlock>[];
  while (reader.remaining >= 12) {
    _skipTaggedPadding(reader);
    if (reader.remaining < 12) {
      break;
    }
    final String signature = reader.readString(4);
    if (signature != '8BIM' && signature != '8B64') {
      throw PsFormatException(message: 'Invalid tagged-block signature "$signature"', source: reader.bytes, offset: reader.baseOffset + reader.offset - 4);
    }
    final String key = reader.readString(4);
    final bool wide = version == PsdVersion.psb && _widePsbTaggedBlocks.contains(key);
    final int length = reader.readLength(wide: wide, label: '$key tagged block');
    final Uint8List data = reader.readBytes(length);
    if (length.isOdd) {
      reader.skip(1);
    }
    result.add(PsdTaggedBlock(key: key, signature: signature, data: data));
  }
  if (reader.remaining != 0) {
    final Uint8List padding = reader.readBytes(reader.remaining);
    if (padding.any((value) => value != 0)) {
      throw const PsFormatException(message: 'Non-zero trailing bytes after tagged blocks');
    }
  }
  return result;
}

/// Skips up to three zero bytes used by writers that align tagged blocks to four bytes.
void _skipTaggedPadding(PsBinaryReader reader) {
  for (int padding = 1; padding <= 3 && reader.remaining >= padding + 4; padding++) {
    final bool zeros = Uint8List.sublistView(reader.bytes, reader.offset, reader.offset + padding).every((value) => value == 0);
    final String signature = String.fromCharCodes(Uint8List.sublistView(reader.bytes, reader.offset + padding, reader.offset + padding + 4));
    if (zeros && (signature == '8BIM' || signature == '8B64')) {
      reader.skip(padding);
      return;
    }
  }
}

/// Serializes Photoshop image resources with even-byte padding.
Uint8List _writeImageResources(List<PsdImageResource> resources) {
  final PsBinaryWriter writer = PsBinaryWriter();
  for (final PsdImageResource resource in resources) {
    _requireFourCharacters(resource.signature, 'image-resource signature');
    if (resource.id < 0 || resource.id > 0xffff) {
      throw PsWriteException(message: 'Image resource id ${resource.id} is outside 0...65535');
    }
    final Uint8List name = _legacyName(resource.name);
    writer
      ..writeString(resource.signature)
      ..writeUint16(resource.id)
      ..writeUint8(name.length)
      ..writeBytes(name);
    if ((name.length + 1).isOdd) {
      writer.writeUint8(0);
    }
    writer
      ..writeUint32(resource.data.length)
      ..writeBytes(resource.data);
    if (resource.data.length.isOdd) {
      writer.writeUint8(0);
    }
  }
  return writer.takeBytes();
}

/// Serializes the complete layer-and-mask section payload.
Uint8List _writeLayerAndMask(PsdDocument document, {required PsdVersion version, required PsdCompression? compressionOverride}) {
  if (document.layers.isEmpty && document.globalLayerMaskData.isEmpty && document.additionalLayerInfo.isEmpty) {
    return Uint8List(0);
  }
  final PsBinaryWriter writer = PsBinaryWriter();
  final PsdTaggedBlock? existingAlternative = _alternativeLayerInfo(document.additionalLayerInfo, document.depth);
  final bool alternativeLayers = document.layers.isNotEmpty && (document.depth == 16 || document.depth == 32 || existingAlternative != null);
  final Uint8List encodedLayers = _writeLayerInfo(document, version: version, compressionOverride: compressionOverride);
  final Uint8List layerInfo = alternativeLayers ? Uint8List(0) : encodedLayers;
  final String alternativeKey = switch (document.depth) {
    16 => 'Lr16',
    32 => 'Lr32',
    _ => 'Layr',
  };
  final List<PsdTaggedBlock> additionalInfo = alternativeLayers
      ? _replaceAlternativeLayerInfo(document.additionalLayerInfo, key: alternativeKey, data: encodedLayers)
      : existingAlternative != null && document.layers.isEmpty
      ? _removeAlternativeLayerInfo(document.additionalLayerInfo, alternativeKey)
      : document.additionalLayerInfo;
  writer
    ..writeLength(layerInfo.length, wide: version == PsdVersion.psb)
    ..writeBytes(layerInfo)
    ..writeUint32(document.globalLayerMaskData.length)
    ..writeBytes(document.globalLayerMaskData)
    ..writeBytes(_writeTaggedBlocks(additionalInfo, version));
  return writer.takeBytes();
}

/// Removes a depth-specific layer block after all model layers were deleted.
List<PsdTaggedBlock> _removeAlternativeLayerInfo(List<PsdTaggedBlock> blocks, String key) => <PsdTaggedBlock>[
  for (final PsdTaggedBlock block in blocks)
    if (block.key != key) block,
];

/// Replaces stale alternative layer blocks with one freshly encoded payload.
List<PsdTaggedBlock> _replaceAlternativeLayerInfo(List<PsdTaggedBlock> blocks, {required String key, required Uint8List data}) {
  final List<PsdTaggedBlock> result = <PsdTaggedBlock>[];
  bool inserted = false;
  for (final PsdTaggedBlock block in blocks) {
    if (block.key == 'Layr' || block.key == 'Lr16' || block.key == 'Lr32') {
      if (!inserted) {
        result.add(PsdTaggedBlock(key: key, signature: block.signature, data: data));
        inserted = true;
      }
    } else {
      result.add(block);
    }
  }
  if (!inserted) {
    result.add(PsdTaggedBlock(key: key, data: data));
  }
  return result;
}

/// Serializes layer records followed by their encoded planar channels.
Uint8List _writeLayerInfo(PsdDocument document, {required PsdVersion version, required PsdCompression? compressionOverride}) {
  if (document.layers.isEmpty) {
    return Uint8List(0);
  }
  if (document.layers.length > 0x7fff) {
    throw const PsWriteException(message: 'PSD supports at most 32767 layer records');
  }
  final List<_EncodedLayer> encodedLayers = <_EncodedLayer>[];
  for (final PsdLayer layer in document.layers) {
    final List<Uint8List> channels = <Uint8List>[];
    for (final PsdChannel channel in layer.channels) {
      final PsdRectangle rectangle = _channelRectangle(layer, channel.id);
      final PsdCompression compression = compressionOverride ?? channel.compression;
      final Uint8List payload = encodePsdChannel(
        compression: compression,
        data: channel.data,
        width: rectangle.width,
        height: rectangle.height,
        depth: document.depth,
        wideRowLengths: version == PsdVersion.psb,
      );
      final PsBinaryWriter encoded = PsBinaryWriter()
        ..writeUint16(compression.code)
        ..writeBytes(payload);
      channels.add(encoded.takeBytes());
    }
    encodedLayers.add(_EncodedLayer(layer: layer, channels: channels));
  }

  final PsBinaryWriter writer = PsBinaryWriter();
  final int count = document.mergedTransparency ? -document.layers.length : document.layers.length;
  writer.writeInt16(count);
  for (final _EncodedLayer encoded in encodedLayers) {
    final PsdLayer layer = encoded.layer;
    _writeRectangle(writer, layer.rectangle);
    writer.writeUint16(layer.channels.length);
    for (int index = 0; index < layer.channels.length; index++) {
      writer
        ..writeInt16(layer.channels[index].id)
        ..writeLength(encoded.channels[index].length, wide: version == PsdVersion.psb);
    }
    _requireFourCharacters(layer.blendMode, 'blend mode');
    if (layer.opacity < 0 || layer.opacity > 255 || layer.clipping < 0 || layer.clipping > 255 || layer.flags < 0 || layer.flags > 255) {
      throw const PsWriteException(message: 'Layer opacity, clipping, and flags must fit in one byte');
    }
    final Uint8List extra = _writeLayerExtra(layer, version);
    writer
      ..writeString('8BIM')
      ..writeString(layer.blendMode)
      ..writeUint8(layer.opacity)
      ..writeUint8(layer.clipping)
      ..writeUint8(layer.flags)
      ..writeUint8(0)
      ..writeUint32(extra.length)
      ..writeBytes(extra);
  }
  for (final _EncodedLayer layer in encodedLayers) {
    layer.channels.forEach(writer.writeBytes);
  }
  if (writer.length.isOdd) {
    writer.writeUint8(0);
  }
  return writer.takeBytes();
}

/// Serializes mask, blending ranges, names, and tagged data for [layer].
Uint8List _writeLayerExtra(PsdLayer layer, PsdVersion version) {
  final PsBinaryWriter writer = PsBinaryWriter();
  final Uint8List mask = layer.mask?.data ?? Uint8List(0);
  writer
    ..writeUint32(mask.length)
    ..writeBytes(mask)
    ..writeUint32(layer.blendingRanges.length)
    ..writeBytes(layer.blendingRanges);
  final Uint8List name = _legacyName(layer.name);
  final int nameStart = writer.length;
  writer
    ..writeUint8(name.length)
    ..writeBytes(name);
  writer.writeZeros((4 - (writer.length - nameStart) % 4) % 4);
  final List<PsdTaggedBlock> blocks = <PsdTaggedBlock>[
    for (final PsdTaggedBlock block in layer.additionalInfo)
      if (block.key != 'luni') block,
    PsdTaggedBlock(key: 'luni', data: _writeUnicodeString(layer.name)),
  ];
  writer.writeBytes(_writeTaggedBlocks(blocks, version));
  return writer.takeBytes();
}

/// Serializes [blocks] with version-specific lengths and even-byte padding.
Uint8List _writeTaggedBlocks(List<PsdTaggedBlock> blocks, PsdVersion version) {
  final PsBinaryWriter writer = PsBinaryWriter();
  for (final PsdTaggedBlock block in blocks) {
    _requireFourCharacters(block.signature, 'tagged-block signature');
    _requireFourCharacters(block.key, 'tagged-block key');
    final bool wide = version == PsdVersion.psb && _widePsbTaggedBlocks.contains(block.key);
    writer
      ..writeString(block.signature)
      ..writeString(block.key)
      ..writeLength(block.data.length, wide: wide)
      ..writeBytes(block.data);
    if (block.data.length.isOdd) {
      writer.writeUint8(0);
    }
  }
  return writer.takeBytes();
}

/// Decodes the last well-formed Unicode layer-name block, when present.
String? _unicodeLayerName(List<PsdTaggedBlock> blocks) {
  for (final PsdTaggedBlock block in blocks.reversed) {
    if (block.key != 'luni' || block.data.length < 4) {
      continue;
    }
    final PsBinaryReader reader = PsBinaryReader(bytes: block.data);
    final int units = reader.readUint32();
    if (units > reader.remaining ~/ 2) {
      throw const PsFormatException(message: 'Truncated Unicode layer name');
    }
    final List<int> codeUnits = <int>[for (int index = 0; index < units; index++) reader.readUint16()];
    return String.fromCharCodes(codeUnits);
  }
  return null;
}

/// Encodes [value] as a length-prefixed big-endian UTF-16 string.
Uint8List _writeUnicodeString(String value) {
  final PsBinaryWriter writer = PsBinaryWriter()..writeUint32(value.codeUnits.length);
  value.codeUnits.forEach(writer.writeUint16);
  return writer.takeBytes();
}

/// Encodes the required legacy one-byte name, replacing unsupported units.
Uint8List _legacyName(String value) {
  final List<int> bytes = <int>[];
  for (final int unit in value.codeUnits.take(255)) {
    bytes.add(unit <= 0xff ? unit : 0x3f);
  }
  return Uint8List.fromList(bytes);
}

/// Reads four signed PSD edges from [reader].
PsdRectangle _readRectangle(PsBinaryReader reader) => PsdRectangle(top: reader.readInt32(), left: reader.readInt32(), bottom: reader.readInt32(), right: reader.readInt32());

/// Writes the four signed edges of [rectangle].
void _writeRectangle(PsBinaryWriter writer, PsdRectangle rectangle) {
  writer
    ..writeInt32(rectangle.top)
    ..writeInt32(rectangle.left)
    ..writeInt32(rectangle.bottom)
    ..writeInt32(rectangle.right);
}

/// Resolves the sample bounds belonging to [channelId] on [layer].
PsdRectangle _channelRectangle(PsdLayer layer, int channelId) {
  if (channelId == -2 && layer.mask != null) {
    return layer.mask!.rectangle;
  }
  if (channelId == -3 && layer.mask?.realRectangle != null) {
    return layer.mask!.realRectangle!;
  }
  return layer.rectangle;
}

/// Replaces placeholder channels while retaining every metadata field.
PsdLayer _copyLayer(PsdLayer layer, List<PsdChannel> channels) => PsdLayer(
  rectangle: layer.rectangle,
  name: layer.name,
  channels: channels,
  blendMode: layer.blendMode,
  opacity: layer.opacity,
  clipping: layer.clipping,
  flags: layer.flags,
  mask: layer.mask,
  blendingRanges: layer.blendingRanges,
  additionalInfo: layer.additionalInfo,
);

/// Resolves a supported PSD enum value or reports its byte location.
T _enumByCode<T>(List<T> values, int code, String label, PsBinaryReader reader) {
  for (final T value in values) {
    final int valueCode = switch (value) {
      PsdVersion(code: final int itemCode) => itemCode,
      PsdColorMode(code: final int itemCode) => itemCode,
      PsdCompression(code: final int itemCode) => itemCode,
      _ => -1,
    };
    if (valueCode == code) {
      return value;
    }
  }
  throw PsFormatException(message: 'Unsupported $label $code', source: reader.bytes, offset: reader.baseOffset + reader.offset);
}

/// Validates header ranges before allocations or serialization.
void _validateHeader({
  required PsdVersion version,
  required int channels,
  required int width,
  required int height,
  required int depth,
  required int maxPixels,
  required bool writing,
}) {
  final void Function(String message) fail = writing ? (message) => throw PsWriteException(message: message) : (message) => throw PsFormatException(message: message);
  if (channels < 1 || channels > 56) {
    fail('Channel count must be between 1 and 56');
  }
  final int dimensionLimit = version == PsdVersion.psd ? 30000 : 300000;
  if (width < 1 || height < 1 || width > dimensionLimit || height > dimensionLimit) {
    fail('${version.name.toUpperCase()} dimensions must be between 1 and $dimensionLimit pixels');
  }
  if (width * height > maxPixels) {
    fail('Canvas area ${width * height} exceeds the configured limit $maxPixels');
  }
  if (depth != 1 && depth != 8 && depth != 16 && depth != 32) {
    fail('Depth must be 1, 8, 16, or 32 bits');
  }
}

/// Ensures that [value] fits a four-byte Photoshop signature field.
void _requireFourCharacters(String value, String label) {
  if (value.length != 4 || value.codeUnits.any((unit) => unit > 0xff)) {
    throw PsWriteException(message: '$label must contain exactly four one-byte characters');
  }
}
