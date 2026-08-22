# PsdKit

PsdKit is a pure Dart reader and writer for Adobe Photoshop PSD and PSB files. It has no runtime package dependency and does not depend on Flutter, making it suitable for Focale's data layer and for command-line tools.

The implementation follows Adobe's [Photoshop File Formats Specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/).

## Supported data

| Feature | Read | Write | Notes |
|---|---:|---:|---|
| PSD and PSB containers | Yes | Yes | Version-specific 32/64-bit lengths |
| 1, 8, 16, and 32-bit channels | Yes | Yes | Samples remain planar and lossless |
| Bitmap, grayscale, indexed, RGB, CMYK, multichannel, duotone, Lab | Yes | Yes | RGBA preview conversion is included |
| RAW, PackBits RLE, ZIP, ZIP prediction | Yes | Yes | ZIP uses the Dart SDK's native zlib codec |
| Raster layers and transparency | Yes | Yes | Negative coordinates are supported |
| Raster-mask metadata and channels | Yes | Yes | Complete mask payloads are retained |
| Groups | Yes | Yes | Exposed through `PsdLayer.sectionType` |
| Unicode names and layer ids | Yes | Yes | `luni`, `lyid`, `lsct`, and `lsdk` helpers |
| Image resources | Preserved | Preserved | Including unknown resources |
| Text, effects, vector paths, adjustments, smart objects | Preserved | Preserved | Available as opaque tagged blocks; semantic decoding is future work |

Unknown image resources and tagged layer blocks are deliberately retained. Reading and rewriting a document therefore does not discard Photoshop-specific information merely because PsdKit does not interpret it yet.

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

To create planar RGB channels from Focale or Flutter pixels:

```dart
final image = PsdRgbaImage(width: width, height: height, bytes: straightRgba);
final channels = PsdPixels.encodeRgb(image);
```

The first three returned planes are red, green, and blue; the optional fourth plane is alpha. Use ids `0`, `1`, `2`, and `-1` respectively when constructing a `PsdLayer`. For a merged image, channels are positional and alpha follows the colour planes.

## Safety and platforms

`PsdReadOptions` limits canvas area, layer count, and decoded allocation size when opening untrusted files. All variable-length sections are parsed through bounded readers.

RAW and RLE work on every Dart platform. ZIP reading and writing use `dart:io` through a conditional import; on platforms without `dart:io`, ZIP operations throw `UnsupportedError`. RLE is the portable write default.

## Development

```sh
dart analyze
dart test
dart run tool/quality_check.dart
```

The quality check enforces Dartdoc on public and private declarations and the project member order: fields, constructors, then methods.

See [Focale integration](doc/focale_integration.md) for the recommended application adapter boundary and round-trip strategy.
