import 'package:psdkit/src/model.dart';

/// Copies a document while replacing only the requested metadata collections.
///
/// Pixel buffers and the layer list retain their identity, including any source
/// encoding or padding associated with them by the codec.
PsdDocument copyPsdDocument(
  PsdDocument document, {
  List<PsdImageResource>? imageResources,
  List<PsdTaggedBlock>? additionalLayerInfo,
}) => PsdDocument(
  version: document.version,
  width: document.width,
  height: document.height,
  channels: document.channels,
  depth: document.depth,
  colorMode: document.colorMode,
  colorModeData: document.colorModeData,
  imageResources: imageResources ?? document.imageResources,
  layers: document.layers,
  mergedImage: document.mergedImage,
  mergedImageCompression: document.mergedImageCompression,
  mergedTransparency: document.mergedTransparency,
  globalLayerMaskData: document.globalLayerMaskData,
  additionalLayerInfo: additionalLayerInfo ?? document.additionalLayerInfo,
);

/// Copies a layer while retaining every field not explicitly replaced.
PsdLayer copyPsdLayer(
  PsdLayer layer, {
  List<PsdChannel>? channels,
  List<PsdTaggedBlock>? additionalInfo,
  int? flags,
}) => PsdLayer(
  rectangle: layer.rectangle,
  name: layer.name,
  channels: channels ?? layer.channels,
  blendMode: layer.blendMode,
  opacity: layer.opacity,
  clipping: layer.clipping,
  flags: flags ?? layer.flags,
  mask: layer.mask,
  blendingRanges: layer.blendingRanges,
  additionalInfo: additionalInfo ?? layer.additionalInfo,
  writesUnicodeName: layer.writesUnicodeName,
);
