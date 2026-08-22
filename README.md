# PsdKit

PsdKit is a pure Dart reader and writer for Adobe Photoshop PSD and PSB files. It has no Flutter or native dependency and does not delegate PSD parsing to a third-party PSD library, making it suitable for image editors and for command-line tools.

The implementation follows Adobe's [Photoshop File Formats Specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/).

## Usage

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';

final Uint8List input = await File('input.psd').readAsBytes();
final PsdDocument document = PsdCodec.decode(input);

final PsdRgbaImage preview = PsdPixels.decodeMerged(document);
print('${preview.width} x ${preview.height}: ${document.layers.length} layers');

final Uint8List output = PsdCodec.encode(
  document,
  options: const PsdWriteOptions(compression: PsdCompression.rle),
);
await File('output.psd').writeAsBytes(output);
```

To create planar RGB channels from Flutter pixels:

```dart
final image = PsdRgbaImage(width: width, height: height, bytes: straightRgba);
final channels = PsdPixels.encodeRgb(image);
```

The first three returned planes are red, green, and blue; the optional fourth plane is alpha. Use ids `0`, `1`, `2`, and `-1` respectively when constructing a `PsdLayer`. For a merged image, channels are positional and alpha follows the colour planes.

## Editable text

`PsdLayer.typeTool` exposes the `TySh` tagged block. Its `content` getter converts Adobe `EngineData` into plain text, orientation, font, font size, RGBA color, tracking, leading, bold/italic decorations, style ranges, and paragraph alignment:

```dart
final PsdTypeTool? typeTool = document.layers.first.typeTool;
if (typeTool != null) {
  print(typeTool.content.text);
  print(typeTool.content.styleAt(0)?.fontFamily);
}
```

Use `withText` to replace only the characters while preserving the original Adobe engine metadata. Style and paragraph run lengths are adjusted automatically. Use `withContent` when formatting changed, or create a new type tool without a source PSD:

```dart
final content = PsdTextContent(
  text: 'Bonjour PSD',
  orientation: PsdTextOrientation.horizontal,
  styleRuns: const [
    PsdTextStyleRun(
      start: 0,
      length: 11,
      style: PsdTextStyle(
        fontFamily: 'Inter-Regular',
        fontSize: 24,
        color: PsdTextColor(alpha: 255, red: 20, green: 30, blue: 40),
      ),
    ),
  ],
);
final typeTool = PsdTypeTool.fromText(
  content: content,
  bounds: const PsdTextBounds(left: 0, top: 0, right: 300, bottom: 80),
);
final textLayer = rasterPreviewLayer.withTypeTool(typeTool);
```

Photoshop stores rendered preview channels alongside editable type metadata. PsdKit encodes both but deliberately does not rasterize fonts; the application must supply the layer channels and merged image matching the text it displays.

## Layer effects

`PsdLayer.effects` decodes modern descriptor effects as well as historical `lrFX` records. Supported semantic families include multiple drop and inner shadows, outer and inner glows, bevel/emboss, satin, color/gradient/pattern overlays, and strokes:

```dart
final effects = layer.effects;
for (final effect in effects?.effects ?? const <PsdLayerEffect>[]) {
  print('${effect.type.name}: ${effect.opacity}% ${effect.blendMode}');
}
```

Every `PsdLayerEffect` retains its complete action descriptor, including unknown Adobe properties. Common properties can be edited directly, while `withProperty` supports advanced descriptor values:

```dart
final shadow = PsdLayerEffect.create(
  type: PsdLayerEffectType.dropShadow,
  blendMode: 'Mltp',
  opacity: 60,
  color: const PsdEffectColor(alpha: 255, red: 0, green: 0, blue: 0),
  angle: 120,
  distance: 8,
  size: 12,
);
final stroke = PsdLayerEffect.create(
  type: PsdLayerEffectType.stroke,
  size: 3,
  strokePosition: PsdStrokePosition.outside,
  color: const PsdEffectColor(alpha: 255, red: 255, green: 255, blue: 255),
);
final editedLayer = layer.withEffects(
  PsdLayerEffects.create(effects: [shadow, stroke]),
);
```

Unchanged modern and legacy blocks round-trip byte for byte. Editing a legacy `lrFX` record upgrades it to modern `lfx2`, avoiding the limitations of the historical fixed structures. PsdKit stores effect definitions but does not rasterize them; the application remains responsible for matching layer preview channels and the merged image.

## Vector paths

`PsdLayer.vectorMask` exposes `vmsk` and `vsms` layer masks. `PsdDocument.namedPaths` exposes saved document paths from Photoshop image resources. Both use `PsdVectorPath`, with semantic subpaths and exact 26-byte source records:

```dart
final mask = layer.vectorMask;
for (final subpath in mask?.path.subpaths ?? const <PsdSubpath>[]) {
  for (final knot in subpath.knots) {
    print('anchor: ${knot.anchor.x}, ${knot.anchor.y}');
  }
}
```

Coordinates are normalized against the PSD canvas. `PsdPathPoint.fromPixels`, `pixelX`, and `pixelY` convert to and from application coordinates. Paths can contain open or closed contours, linked or independent cubic Bézier handles, and combine/subtract/intersect/exclude operations:

```dart
final path = PsdVectorPath.fromSubpaths(
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
final editedLayer = layer.withVectorMask(PsdVectorMask(path: path));
```

Use `PsdDocument.withNamedPaths` for saved document paths. Clipboard, fill-rule, initial-fill, and unknown path records are retained so unchanged masks and resources can round-trip byte for byte.

## Fill and adjustment layers

`PsdLayer.adjustment` recognizes Photoshop's fill and adjustment keys. Brightness/contrast, levels, curves, exposure, hue/saturation, color balance, photo filter, channel mixer, invert, posterize, threshold, and selective color have typed models. Solid color, gradient, pattern, vibrance, black and white, and color lookup expose their complete action descriptor:

```dart
final adjustment = layer.adjustment;
if (adjustment case PsdCurvesAdjustment(:final curves)) {
  for (final curve in curves) {
    print('channel ${curve.channel}: ${curve.points.length} points');
  }
}
```

Create or replace an adjustment with `PsdLayer.withAdjustment`. For example, this makes a threshold layer while preserving unrelated layer metadata:

```dart
final editedLayer = layer.withAdjustment(
  PsdSingleValueAdjustment(
    type: PsdAdjustmentType.threshold,
    value: 128,
  ),
);
```

Unknown legacy hue/saturation and gradient-map variants are returned as `PsdRawAdjustment`; their exact payload remains writable. Descriptor-backed values retain unknown Adobe properties and can be changed with `PsdDescriptorAdjustment.withProperty`. PsdKit stores the editable settings but does not render their visual result, so Focale remains responsible for the preview channels and merged image.

## Smart objects

`PsdLayer.smartObject` decodes modern `SoLd`/`SoLE` descriptors and historical `plLd` records. It exposes the linked-resource identifier, affine and non-affine corner transforms, warp metadata, page information, and the complete Adobe descriptor:

```dart
final smartObject = layer.smartObject;
final linkedFile = document.linkedResourceFor(layer);
print('${linkedFile?.name}: ${linkedFile?.data?.length ?? 0} embedded bytes');
```

`PsdDocument.linkedResources` decodes `lnkD`, `lnk2`, and `lnk3` blocks. Embedded `liFD` resources expose their complete file bytes; external `liFE` resources expose their descriptor, timestamp, and expected file size; historical `liFA` aliases remain available as exact bytes. Embedded PSD or PSB content can be opened recursively:

```dart
final bytes = linkedFile?.data;
if (bytes != null &&
    bytes.length >= 4 &&
    bytes[0] == 0x38 &&
    bytes[1] == 0x42 &&
    bytes[2] == 0x50 &&
    bytes[3] == 0x53) {
  final nested = PsdCodec.decode(bytes);
  print('${nested.width} x ${nested.height}');
}
```

Use `PsdDescriptorSmartObject.withLinkedResourceId`, `withTransform`, and `withProperty` to edit placed-layer metadata. Use `PsdLinkedResource.withData` to replace embedded content, then attach the updated resource list with `PsdDocument.withLinkedResources`. Exact original block grouping can instead be retained through `linkedResourceBlocks` and `withLinkedResourceBlocks`.

PsdKit deliberately does not access paths found in external-link descriptors. Focale should resolve those paths through its own permission and file-storage layer. Photoshop rendering, smart filters, and live re-rasterization also remain application responsibilities; the PSD structures and nested files are imported and exported without loss.

## Image resources

Every `PsdImageResource` can be decoded through its `decoded` getter. Standard resources expose typed values for resolution and units, colors, print settings, grids and guides, alpha channels, halftone and transfer curves, thumbnails, ICC headers, XMP, URL lists, pixel aspect ratio, application versions, selected layers, descriptors, slices, and document paths:

```dart
final resolution = document.decodedImageResource(
  PsdImageResourceIds.resolutionInfo,
);
if (resolution case PsdResolutionInfo(:final horizontal, :final vertical)) {
  print('$horizontal × $vertical dpi');
}

final xmp = document.decodedImageResource(PsdImageResourceIds.xmp);
if (xmp case PsdTextImageResource(:final value)) {
  print(value);
}
```

Resources can be inserted or replaced without rebuilding the rest of the document:

```dart
final edited = document.withImageResourceData(
  PsdResolutionInfo.fromValues(horizontal: 300, vertical: 300),
);
final withoutXmp = edited.withoutImageResource(PsdImageResourceIds.xmp);
```

Formats governed by separate standards, including IPTC and EXIF, are exposed as `PsdBinaryMetadataResource`; ICC profiles additionally expose their standard header fields. Plug-in resources, undocumented identifiers, and malformed standard payloads use `PsdRawImageResource`. Both retain their complete bytes, resource name, and signature when the enclosing block is left unchanged.

## Supported data

| Feature                                                           | Read | Write | Notes                                                                                                 |
|-------------------------------------------------------------------|-----:|------:|-------------------------------------------------------------------------------------------------------|
| PSD and PSB containers                                            |  Yes |   Yes | Version-specific 32/64-bit lengths                                                                    |
| 1, 8, 16, and 32-bit channels                                     |  Yes |   Yes | Samples remain planar and lossless                                                                    |
| Bitmap, grayscale, indexed, RGB, CMYK, multichannel, duotone, Lab |  Yes |   Yes | RGBA preview conversion is included                                                                   |
| RAW, PackBits RLE, ZIP, ZIP prediction                            |  Yes |   Yes | ZIP uses the pure-Dart `zcodec` implementation                                                        |
| Raster layers and transparency                                    |  Yes |   Yes | Negative coordinates are supported                                                                    |
| Raster-mask metadata and channels                                 |  Yes |   Yes | Complete mask payloads are retained                                                                   |
| Groups                                                            |  Yes |   Yes | Exposed through `PsdLayer.sectionType`                                                                |
| Unicode names and layer ids                                       |  Yes |   Yes | `luni`, `lyid`, `lsct`, and `lsdk` helpers                                                            |
| Editable text layers                                              |  Yes |   Yes | Unicode, transforms, bounds, orientation, fonts, sizes, colors, style ranges, and paragraph alignment |
| Layer effects                                                     |  Yes |   Yes | Modern `lfx2`/`lmfx`, legacy `lrFX`, repeated effects, and complete descriptor preservation           |
| Vector masks and document paths                                   |  Yes |   Yes | Open/closed cubic Bézier paths, Boolean operations, fill rules, and unknown record preservation       |
| Fill and adjustment layers                                        |  Yes |   Yes | Typed common adjustments, descriptor-backed modern settings, and raw fallback preservation            |
| Smart objects and linked files                                    |  Yes |   Yes | Modern and legacy placed layers; embedded, external, and alias resources                              |
| Image resources                                                   |  Yes |   Yes | Typed standard resources; external, private, and unknown payloads remain losslessly accessible        |

Unknown image resources and tagged layer blocks are deliberately retained. Reading and rewriting a document therefore does not discard Photoshop-specific information merely because PsdKit does not interpret it yet.

“Yes” above means that PsdKit semantically exposes the listed structures and can write them back. It does not mean that every Photoshop resource is interpreted or rasterized: undocumented and currently unsupported image resources, tagged blocks, descriptor variants, smart filters, and application rendering remain opaque but loss-preserved. This distinction is intentional; the public Adobe specification describes many structures without defining their visual interpretation.

## Safety and platforms

`PsdReadOptions` limits canvas area, layer count, and decoded allocation size when opening untrusted files. All variable-length sections are parsed through bounded readers, and ZIP output is capped while it is being decompressed rather than after allocation.

## Development

```sh
dart analyze
dart test
dart run tool/quality_check.dart
dart run tool/document_corpus_check.dart /path/to/psd-corpus
dart run tool/text_corpus_check.dart /path/to/psd-corpus
dart run tool/effects_corpus_check.dart /path/to/psd-corpus
dart run tool/paths_corpus_check.dart /path/to/psd-corpus
dart run tool/adjustments_corpus_check.dart /path/to/psd-corpus
dart run tool/smart_objects_corpus_check.dart /path/to/psd-corpus
dart run tool/image_resources_inventory.dart /path/to/psd-corpus
dart run tool/image_resources_corpus_check.dart /path/to/psd-corpus
```

The quality check enforces Dartdoc on public and private declarations and the project member order: fields, constructors, then methods.
