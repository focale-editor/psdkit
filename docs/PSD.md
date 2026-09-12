# PSD and PSB technical reference

This document describes how PsdKit represents Photoshop data, which parts of PSD and PSB it supports, and the responsibilities that remain with the host application. For a task-oriented introduction, start with the [README](../README.md).

The PSD and PSB parser and writer are implemented in pure Dart rather than delegated to a third-party PSD library. The implementation follows Adobe's [Photoshop File Formats Specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/). Shared Photoshop binary primitives and Action Descriptors come from [`pscore`](https://github.com/focale-editor/pscore). PsdKit re-exports that API, so consumers normally only need to import `package:psdkit/psdkit.dart`.

## Reading and writing documents

`PsdCodec.decode` reads a complete PSD or PSB byte stream into an in-memory `PsdDocument`. `PsdCodec.encode` writes that model back to bytes:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';

final Uint8List input = await File('input.psd').readAsBytes();
final PsdDocument document = PsdCodec.decode(input);

final Uint8List output = PsdCodec.encode(
  document,
  options: const PsdWriteOptions(compression: PsdCompression.rle),
);
await File('output.psd').writeAsBytes(output, flush: true);
```

`PsdWriteOptions.version` can override the source container version. Use `PsdVersion.psb` when writing a large-document PSB.

## Updating copy-based models

Editing methods such as `withTypeTool`, `withEffects`, and `withAdjustment` return an updated `PsdLayer`. Place that layer in the document's flat layer list before encoding it. The following helper copies all other document data unchanged:

```dart
PsdDocument replaceLayer(
  PsdDocument document, {
  required int index,
  required PsdLayer replacement,
}) {
  final List<PsdLayer> layers = List<PsdLayer>.of(document.layers);
  layers[index] = replacement;
  return PsdDocument(
    version: document.version,
    width: document.width,
    height: document.height,
    channels: document.channels,
    depth: document.depth,
    colorMode: document.colorMode,
    colorModeData: document.colorModeData,
    imageResources: document.imageResources,
    layers: layers,
    mergedImage: document.mergedImage,
    mergedImageCompression: document.mergedImageCompression,
    mergedTransparency: document.mergedTransparency,
    globalLayerMaskData: document.globalLayerMaskData,
    additionalLayerInfo: document.additionalLayerInfo,
  );
}
```

Document-level helpers such as `withImageResourceData`, `withNamedPaths`, and `withLinkedResources` already return a complete updated `PsdDocument`.

## Progressive output

For large files, use the seekable progressive writer instead of retaining the encoded document in memory:

```dart
final PsdStreamDocument streamed = PsdStreamDocument.fromDocument(document);
final int byteLength = await PsdCodec.encodeTo(
  streamed,
  output,
  options: const PsdWriteOptions(
    version: PsdVersion.psb,
    compression: PsdCompression.rle,
  ),
  rowBatchSize: 32,
);
```

In this example, `output` implements `PsdRandomAccessOutput` and remains owned by the caller. `encodeTo` flushes it but does not close it. `PsdStreamDocument.fromDocument` is a compatibility adapter over planes that are already resident in memory. Applications that require bounded memory should provide custom `PsdPlanarSource` implementations that read rows from tiles, temporary files, or another backing store.

Progressive output supports RAW and row-local PackBits RLE. ZIP compression requires the byte-oriented `PsdCodec.encode` API.

## Pixel and channel model

PsdKit stores decoded channel samples as uncompressed planar data. `PsdPixels` converts supported document color modes to 8-bit, straight-alpha RGBA for display.

To create planar RGB channels from RGBA pixels:

```dart
final PsdRgbaImage image = PsdRgbaImage(
  width: width,
  height: height,
  bytes: straightRgba,
);
final List<Uint8List> channels = PsdPixels.encodeRgb(image);
```

The first three returned planes are red, green, and blue. The optional fourth plane is alpha. Use channel ids `0`, `1`, `2`, and `-1` respectively when constructing a `PsdLayer`. For a merged image, channels are positional and alpha follows the color planes.

## Editable text

`PsdLayer.typeTool` exposes the modern `TySh` tagged block. Its `content` getter converts Adobe `EngineData` into plain text and editable character and paragraph runs. Supported properties include font metadata, grayscale/RGB/CMYK fill and stroke colors, scaling, kerning, leading, OpenType flags, decorations, indents, spacing, hyphenation, composer settings, baseline grid, antialiasing, and point- or box-text geometry:

```dart
final PsdTypeTool? typeTool = document.layers.first.typeTool;
if (typeTool != null) {
  print(typeTool.content.text);
  print(typeTool.content.styleAt(0)?.fontFamily);
}
```

Use `withText` to replace only the characters while preserving the original Adobe engine metadata. Style and paragraph run lengths are adjusted automatically. Use `withContent` when formatting changed, or create a new type tool without a source PSD:

```dart
final PsdTextContent content = PsdTextContent(
  text: 'Bonjour PSD',
  orientation: PsdTextOrientation.horizontal,
  styleRuns: const [
    PsdTextStyleRun(
      start: 0,
      length: 11,
      style: PsdTextStyle(
        fontFamily: 'Inter-Regular',
        fontSize: 24,
        color: PsdTextColor(
          alpha: 255,
          red: 20,
          green: 30,
          blue: 40,
        ),
      ),
    ),
  ],
);
final PsdTypeTool typeTool = PsdTypeTool.fromText(
  content: content,
  bounds: const PsdTextBounds(
    left: 0,
    top: 0,
    right: 300,
    bottom: 80,
  ),
  descriptorBounds: PsdTextDescriptorBounds.pixels(
    left: 0,
    top: 0,
    right: 300,
    bottom: 80,
  ),
);
final PsdLayer textLayer = rasterPreviewLayer.withTypeTool(typeTool);
```

The final `TySh` bounds are single-precision values and remain separate from optional unit-bearing `bounds` and `boundingBox` descriptor values. `PsdTextContent.hasShapeMetadata` distinguishes explicit point text from an older or malformed engine payload whose rendered shape tree is absent, allowing consumers to apply a compatibility fallback safely. Common warp settings are available through `PsdTypeTool.warp` and `withWarp`; unknown custom-warp descriptor entries remain untouched.

Photoshop 5.0 and 5.5 `tySh` records are available through `PsdLayer.legacyTypeTool` and `withLegacyTypeTool`. Their published face, style, line, color, and transform structures can be decoded and re-encoded with `PsdLegacyTypeToolCodec`. Document-level `Txt2` bytes are available through `PsdDocument.globalTextEngineData`; its `structure` getter provides an immutable representation of Adobe text-engine dictionaries and arrays.

Photoshop stores rendered preview channels alongside editable type metadata. PsdKit encodes both but deliberately does not rasterize fonts. The application must supply layer channels and a merged image matching the text it displays.

## Layer effects

`PsdLayer.effects` decodes modern descriptor effects as well as historical `lrFX` records. Supported semantic families include multiple drop and inner shadows, outer and inner glows, bevel and emboss, satin, color/gradient/pattern overlays, and strokes:

```dart
final PsdLayerEffects? effects = layer.effects;
for (final PsdLayerEffect effect in effects?.effects ?? const <PsdLayerEffect>[]) {
  print('${effect.type.name}: ${effect.opacity}% ${effect.blendMode}');
}
```

Every `PsdLayerEffect` retains its complete action descriptor, including unknown Adobe properties. Common properties can be edited directly, while `withProperty` supports advanced descriptor values:

```dart
final PsdLayerEffect shadow = PsdLayerEffect.create(
  type: PsdLayerEffectType.dropShadow,
  blendMode: 'Mltp',
  opacity: 60,
  color: const PsdEffectColor(
    alpha: 255,
    red: 0,
    green: 0,
    blue: 0,
  ),
  angle: 120,
  distance: 8,
  size: 12,
);
final PsdLayerEffect stroke = PsdLayerEffect.create(
  type: PsdLayerEffectType.stroke,
  size: 3,
  strokePosition: PsdStrokePosition.outside,
  color: const PsdEffectColor(
    alpha: 255,
    red: 255,
    green: 255,
    blue: 255,
  ),
);
final PsdLayer editedLayer = layer.withEffects(
  PsdLayerEffects.create(effects: [shadow, stroke]),
);
```

Unchanged modern and legacy blocks round-trip byte for byte. Editing a legacy `lrFX` record upgrades it to modern `lfx2`, avoiding the limitations of the historical fixed structures. PsdKit stores effect definitions but does not rasterize them; the application remains responsible for matching layer preview channels and the merged image.

## Layer compositions

`PsdLayer.layerCompData` decodes the per-layer `shmd` and `cmls` metadata used by Photoshop layer compositions. It exposes historical visibility and position together with the complete blending descriptor, layer effects, opacity, fill opacity, and channel-specific Blend If ranges:

```dart
final PsdLayerCompLayerState? compState =
    layer.layerCompData?.statesByCompIdentifier[42];
print(compState?.visible);
print(compState?.blendOptions?.opacityPercent);
print(compState?.layerEffects?.effects.length);
```

Use `PsdLayerCompLayerData.create`, `PsdLayerCompLayerState.create`, and `withLayerCompData` to write editable states. Unrelated shared metadata and unknown descriptor properties remain intact when the original descriptors are retained. The document-wide composition catalog remains available as the typed descriptor image resource with id `PsdImageResourceIds.layerComps`.

## Vector paths

`PsdLayer.vectorMask` exposes `vmsk` and `vsms` layer masks. `PsdDocument.namedPaths` exposes saved document paths from Photoshop image resources. Both use `PsdVectorPath`, with semantic subpaths and exact 26-byte source records:

```dart
final PsdVectorMask? mask = layer.vectorMask;
for (final PsdSubpath subpath
    in mask?.path.subpaths ?? const <PsdSubpath>[]) {
  for (final PsdBezierKnot knot in subpath.knots) {
    print('anchor: ${knot.anchor.x}, ${knot.anchor.y}');
  }
}
```

Coordinates are normalized against the PSD canvas. `PsdPathPoint.fromPixels`, `pixelX`, and `pixelY` convert to and from application coordinates. Paths can contain open or closed contours, linked or independent cubic Bézier handles, and combine, subtract, intersect, or exclude operations:

```dart
final PsdVectorPath path = PsdVectorPath.fromSubpaths(
  subpaths: const [
    PsdSubpath(
      closed: true,
      operation: 1,
      knots: [
        PsdBezierKnot.corner(PsdPathPoint(x: 0.1, y: 0.1)),
        PsdBezierKnot.corner(PsdPathPoint(x: 0.9, y: 0.1)),
        PsdBezierKnot.corner(PsdPathPoint(x: 0.9, y: 0.9)),
      ],
    ),
  ],
);
final PsdLayer editedLayer = layer.withVectorMask(
  PsdVectorMask(path: path),
);
```

Use `PsdDocument.withNamedPaths` for saved document paths. Clipboard, fill-rule, initial-fill, and unknown path records are retained so unchanged masks and resources can round-trip byte for byte.

## Fill and adjustment layers

`PsdLayer.adjustment` recognizes Photoshop fill and adjustment keys. Brightness/contrast, levels, curves, exposure, hue/saturation, color balance, photo filter, channel mixer, invert, posterize, threshold, and selective color have typed models. Solid color, gradient, pattern, vibrance, black and white, and color lookup expose their complete action descriptor:

```dart
final PsdAdjustment? adjustment = layer.adjustment;
if (adjustment case PsdCurvesAdjustment(:final curves)) {
  for (final PsdCurve curve in curves) {
    print('channel ${curve.channel}: ${curve.points.length} points');
  }
}
```

Create or replace an adjustment with `PsdLayer.withAdjustment`. For example, this creates a threshold layer while preserving unrelated layer metadata:

```dart
final PsdLayer editedLayer = layer.withAdjustment(
  PsdSingleValueAdjustment(
    type: PsdAdjustmentType.threshold,
    value: 128,
  ),
);
```

Unknown legacy hue/saturation and gradient-map variants are returned as `PsdRawAdjustment`; their exact payload remains writable. Descriptor-backed values retain unknown Adobe properties and can be changed with `PsdDescriptorAdjustment.withProperty`. PsdKit stores the editable settings but does not render their visual result, so the host application remains responsible for preview channels and the merged image.

## Smart objects

`PsdLayer.smartObject` decodes modern `SoLd` and `SoLE` descriptors and historical `plLd` records. It exposes the linked-resource identifier, affine and non-affine corner transforms, warp metadata, page information, and the complete Adobe descriptor:

```dart
final PsdSmartObjectLayerData? smartObject = layer.smartObject;
final PsdLinkedResource? linkedFile = document.linkedResourceFor(layer);
print('${linkedFile?.name}: ${linkedFile?.data?.length ?? 0} embedded bytes');
```

`PsdDocument.linkedResources` decodes `lnkD`, `lnk2`, and `lnk3` blocks. Embedded `liFD` resources expose their complete file bytes; external `liFE` resources expose their descriptor, timestamp, and expected file size; historical `liFA` aliases remain available as exact bytes. Embedded PSD or PSB content can be opened recursively:

```dart
final Uint8List? bytes = linkedFile?.data;
if (bytes != null &&
    bytes.length >= 4 &&
    bytes[0] == 0x38 &&
    bytes[1] == 0x42 &&
    bytes[2] == 0x50 &&
    bytes[3] == 0x53) {
  final PsdDocument nested = PsdCodec.decode(bytes);
  print('${nested.width} × ${nested.height}');
}
```

Use `PsdDescriptorSmartObject.withLinkedResourceId`, `withTransform`, and `withProperty` to edit placed-layer metadata. Use `PsdLinkedResource.withData` to replace embedded content, then attach the updated resource list with `PsdDocument.withLinkedResources`. Exact original block grouping can instead be retained through `linkedResourceBlocks` and `withLinkedResourceBlocks`.

PsdKit deliberately does not access paths found in external-link descriptors. The host application should resolve those paths through its own permission and file-storage layer. Photoshop rendering, smart filters, and live re-rasterization also remain application responsibilities; PSD structures and nested files are imported and exported without loss.

## Image resources

Every `PsdImageResource` can be decoded through its `decoded` getter. Standard resources expose typed values for resolution and units, colors, print settings, grids and guides, alpha channels, halftone and transfer curves, thumbnails, ICC headers, XMP, URL lists, pixel aspect ratio, application versions, selected layers, descriptors, slices, and document paths:

```dart
final PsdImageResourceData? resolution = document.decodedImageResource(
  PsdImageResourceIds.resolutionInfo,
);
if (resolution case PsdResolutionInfo(:final horizontal, :final vertical)) {
  print('$horizontal × $vertical dpi');
}

final PsdImageResourceData? xmp = document.decodedImageResource(
  PsdImageResourceIds.xmp,
);
if (xmp case PsdTextImageResource(:final value)) {
  print(value);
}
```

Resources can be inserted or replaced without rebuilding the rest of the document:

```dart
final PsdDocument edited = document.withImageResourceData(
  PsdResolutionInfo.fromValues(horizontal: 300, vertical: 300),
);
final PsdDocument withoutXmp = edited.withoutImageResource(
  PsdImageResourceIds.xmp,
);
```

Formats governed by separate standards, including IPTC and EXIF, are exposed as `PsdBinaryMetadataResource`; ICC profiles additionally expose their standard header fields. Plug-in resources, undocumented identifiers, and malformed standard payloads use `PsdRawImageResource`. Both retain their complete bytes, resource name, and signature when the enclosing block is left unchanged.

## Supported data

| Feature                                                               | Read | Write | Notes                                                                                                 |
|-----------------------------------------------------------------------|-----:|------:|-------------------------------------------------------------------------------------------------------|
| PSD and PSB containers                                                |  Yes |   Yes | Version-specific 32-bit and 64-bit lengths                                                            |
| 1-, 8-, 16-, and 32-bit channels                                      |  Yes |   Yes | Samples remain planar and lossless                                                                    |
| Bitmap, grayscale, indexed, RGB, CMYK, multichannel, duotone, and Lab |  Yes |   Yes | RGBA preview conversion is included                                                                   |
| RAW, PackBits RLE, ZIP, and ZIP prediction                            |  Yes |   Yes | ZIP uses the pure-Dart `zcodec` implementation                                                        |
| Raster layers and transparency                                        |  Yes |   Yes | Negative coordinates are supported                                                                    |
| Raster-mask metadata and channels                                     |  Yes |   Yes | Complete mask payloads are retained                                                                   |
| Groups                                                                |  Yes |   Yes | Exposed through `PsdLayer.sectionType`                                                                |
| Unicode names and layer ids                                           |  Yes |   Yes | `luni`, `lyid`, `lsct`, and `lsdk` helpers                                                            |
| Editable text layers                                                  |  Yes |   Yes | Unicode, transforms, bounds, orientation, fonts, sizes, colors, style ranges, and paragraph alignment |
| Layer effects                                                         |  Yes |   Yes | Modern `lfx2`/`lmfx`, legacy `lrFX`, repeated effects, and complete descriptor preservation           |
| Layer-composition states                                              |  Yes |   Yes | `cmls` visibility, position, opacity, blending, Blend If, and effects                                 |
| Vector masks and document paths                                       |  Yes |   Yes | Open and closed cubic Bézier paths, Boolean operations, fill rules, and unknown record preservation   |
| Fill and adjustment layers                                            |  Yes |   Yes | Typed common adjustments, descriptor-backed modern settings, and raw fallback preservation            |
| Smart objects and linked files                                        |  Yes |   Yes | Modern and legacy placed layers; embedded, external, and alias resources                              |
| Image resources                                                       |  Yes |   Yes | Typed standard resources; external, private, and unknown payloads remain losslessly accessible        |

"Yes" means that PsdKit semantically exposes the listed structure and can write it back. It does not mean that every Photoshop resource is interpreted or rasterized. Undocumented or unsupported resources, tagged blocks, descriptor variants, smart filters, and application-specific rendering remain opaque but are preserved when possible.

Unknown image resources and tagged layer blocks are deliberately retained. Reading and rewriting a document therefore does not discard Photoshop-specific information merely because PsdKit does not interpret it yet. This distinction is intentional: the public Adobe specification describes many structures without defining their visual interpretation.

## Safety and platform behavior

`PsdReadOptions` limits canvas area, layer count, and decoded allocation size when opening untrusted files. All variable-length sections are parsed through bounded readers, and ZIP output is capped while it is being decompressed rather than after allocation.

Progressive RAW and RLE output retains only a bounded sample-row batch and a bounded batch of RLE row lengths while writing. Metadata blocks still need to be resident in memory.

PsdKit has no native or Flutter dependency. File-system access, external smart-object resolution, permissions, and display integration belong to the host application.

## Corpus validation

The repository includes targeted corpus tools for exercising the parser against collections of real PSD and PSB files:

```sh
dart run tool/document_corpus_check.dart /path/to/psd-corpus
dart run tool/text_corpus_check.dart /path/to/psd-corpus
dart run tool/effects_corpus_check.dart /path/to/psd-corpus
dart run tool/paths_corpus_check.dart /path/to/psd-corpus
dart run tool/adjustments_corpus_check.dart /path/to/psd-corpus
dart run tool/smart_objects_corpus_check.dart /path/to/psd-corpus
dart run tool/image_resources_inventory.dart /path/to/psd-corpus
dart run tool/image_resources_corpus_check.dart /path/to/psd-corpus
```

`dart run tool/quality_check.dart` enforces Dartdoc on public and private declarations and the project member order: fields, constructors, then methods.
