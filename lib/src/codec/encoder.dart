part of '../codec.dart';

/// Holds a layer and its encoded channel payloads during writing.
final class _EncodedLayer {
  /// Layer metadata to serialize.
  final PsdLayer layer;

  /// Encoded channels in record order.
  final List<_EncodedChannel> channels;

  /// Creates a serialized-channel staging value.
  const _EncodedLayer({required this.layer, required this.channels});
}

/// One compressed channel payload and the marker that introduces it.
///
/// The marker is kept apart from the payload so that a channel's samples are
/// never copied merely to prepend two bytes.
final class _EncodedChannel {
  /// Encoding applied to [payload].
  final PsdCompression compression;

  /// Compressed samples, without the two-byte compression marker.
  final Uint8List payload;

  /// Creates one encoded channel.
  const _EncodedChannel({required this.compression, required this.payload});

  /// Stored byte length, including the compression marker.
  int get length => payload.length + 2;

  /// Writes the marker followed by the payload.
  void writeTo(PsBinaryWriter writer) => writer
    ..writeUint16(compression.code)
    ..writeBytes(payload);
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
    final List<_EncodedChannel> channels = <_EncodedChannel>[];
    for (final PsdChannel channel in layer.channels) {
      final PsdRectangle rectangle = _channelRectangle(layer, channel.id);
      final PsdCompression compression = compressionOverride ?? channel.compression;
      channels.add(
        _EncodedChannel(
          compression: compression,
          payload:
              _SourceEncoding.reuse([channel.data], geometry: (rectangle.width, rectangle.height, document.depth, false), compression: compression, wideRowLengths: version == PsdVersion.psb) ??
              encodePsdChannel(
                compression: compression,
                data: channel.data,
                width: rectangle.width,
                height: rectangle.height,
                depth: document.depth,
                wideRowLengths: version == PsdVersion.psb,
              ),
        ),
      );
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
    for (final _EncodedChannel channel in layer.channels) {
      channel.writeTo(writer);
    }
  }
  final int? sourcePadding = _layerInfoPadding[document.layers];
  if (sourcePadding != null && (writer.length + sourcePadding).isEven) {
    writer.writeZeros(sourcePadding);
  } else if (writer.length.isOdd) {
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
  writer.writeBytes(_writeTaggedBlocks(_layerBlocksWithName(layer), version));
  return writer.takeBytes();
}
