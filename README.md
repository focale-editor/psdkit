# PsdKit

Read, inspect, edit, and write Adobe Photoshop PSD and PSB files in Dart.

PsdKit is intended for applications that need to work with Photoshop documents without launching Photoshop. It lets you access the canvas, layers, previews, editable content, and document metadata while preserving Photoshop data that your application does not change.

It is written in pure Dart, with no Flutter or native dependency, so the same API can be used in Flutter applications, command-line tools, and server-side Dart programs.

## Installation

Add PsdKit to a Dart project:

```sh
dart pub add psdkit
```

For a Flutter project, use `flutter pub add psdkit` instead.

## Quick start

Open a document, inspect its layers, generate a display-ready preview, and save it again:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';

final Uint8List input = await File('input.psd').readAsBytes();
final PsdDocument document = PsdCodec.decode(input);

print('${document.width} × ${document.height}');
for (final PsdLayer layer in document.layers) {
  print('${layer.visible ? 'visible' : 'hidden'}: ${layer.name}');
}

final PsdRgbaImage preview = PsdPixels.decodeMerged(document);
print('${preview.bytes.length} RGBA bytes');

final Uint8List output = PsdCodec.encode(document);
await File('output.psd').writeAsBytes(output, flush: true);
```

Most editing helpers use a copy-based API: they return updated values and leave the source value untouched.

## Common tasks

### Display a document or layer

PsdKit converts the merged document preview or an individual raster layer to an 8-bit RGBA buffer:

```dart
final PsdRgbaImage documentPreview = PsdPixels.decodeMerged(document);
final PsdLayer rasterLayer = document.layers.firstWhere(
  (layer) => layer.channels.isNotEmpty,
);
final PsdRgbaImage layerPreview = PsdPixels.decodeLayer(
  document,
  rasterLayer,
);
```

The returned bytes can be passed to the image API used by your application.

### Read or replace editable text

Text layers expose their characters and formatting without requiring knowledge of the PSD text format:

```dart
for (final PsdLayer layer in document.layers) {
  if (layer.typeTool case final PsdTypeTool text) {
    print('${layer.name}: ${text.content.text}');

    final PsdLayer editedLayer = layer.withTypeTool(
      text.withText('Updated copy'),
    );
    // Place editedLayer in the PsdDocument that you encode.
  }
}
```

`withText` keeps the existing formatting and adjusts its ranges to the new text. Use `withContent` when you also need to change fonts, colors, paragraphs, or text geometry. The technical reference shows how to [place an edited layer back into a document](docs/PSD.md#updating-copy-based-models).

### Work with other Photoshop features

The most common entry points are organized around what an application needs to do:

| Goal                                      | API                                                                         |
|-------------------------------------------|-----------------------------------------------------------------------------|
| Inspect or change layer effects           | `layer.effects`, `layer.withEffects(...)`                                   |
| Read or change layer-composition states   | `layer.layerCompData`, `layer.withLayerCompData(...)`                       |
| Inspect or replace a vector mask          | `layer.vectorMask`, `layer.withVectorMask(...)`                             |
| Read or change a fill or adjustment layer | `layer.adjustment`, `layer.withAdjustment(...)`                             |
| Find the file used by a smart object      | `document.linkedResourceFor(layer)`                                         |
| Read saved document paths                 | `document.namedPaths`                                                       |
| Read or update document metadata          | `document.decodedImageResource(...)`, `document.withImageResourceData(...)` |

The [PSD and PSB technical reference](docs/PSD.md) contains examples for each feature and explains how they map to Photoshop data.

### Create a new document

New PSD documents can be assembled from RGBA pixels, raster layers, and editable feature models. See the complete [document creation example](example/psdkit_example.dart).

## Rendering expectations

PsdKit reads and writes the editable information stored in a PSD, but it is not a Photoshop rendering engine. When an application changes text, effects, adjustments, smart objects, or similar features, it must also provide raster layer pixels and a merged preview that visually match those changes.

This separation is useful for editors: PsdKit handles the file and its editable data, while the application remains in control of rendering.

## Compatibility and large files

PsdKit reads and writes both PSD and PSB documents, including common color modes, channel depths, compression methods, raster layers, text, effects, paths, adjustments, smart objects, and image resources. Unknown resources and layer data are retained whenever possible so an edit does not unnecessarily discard Photoshop-specific information.

For very large documents, a progressive writer can stream pixel rows to a seekable destination. Defensive read limits are also available when opening untrusted files. See [PSD and PSB technical reference](docs/PSD.md) for the full support matrix, limitations, memory model, and safety options.

## More documentation

- [PSD and PSB technical reference](docs/PSD.md)
- [API reference](https://pub.dev/documentation/psdkit/latest/)
- [Document creation example](example/psdkit_example.dart)

## Development

Run the standard project checks with:

```sh
dart format .
dart analyze
dart test
dart run tool/quality_check.dart
```

Additional corpus validation commands are documented in the [technical reference](docs/PSD.md#corpus-validation).
