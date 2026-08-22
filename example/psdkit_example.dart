import 'dart:io';
import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';

/// Writes a small layered RGB document to the requested path.
Future<void> main(List<String> arguments) async {
  final String path = arguments.isEmpty ? 'example.psd' : arguments.first;
  final PsdRgbaImage pixels = PsdRgbaImage(
    width: 2,
    height: 2,
    bytes: Uint8List.fromList(<int>[
      255,
      0,
      0,
      255,
      0,
      255,
      0,
      255,
      0,
      0,
      255,
      255,
      255,
      255,
      255,
      128,
    ]),
  );
  final List<Uint8List> planes = PsdPixels.encodeRgb(pixels);
  const PsdRectangle bounds = PsdRectangle.fromSize(width: 2, height: 2);
  final PsdDocument document = PsdDocument(
    width: 2,
    height: 2,
    channels: 4,
    depth: 8,
    colorMode: PsdColorMode.rgb,
    layers: <PsdLayer>[
      PsdLayer(
        rectangle: bounds,
        name: 'PsdKit example',
        channels: <PsdChannel>[
          PsdChannel(id: 0, data: planes[0]),
          PsdChannel(id: 1, data: planes[1]),
          PsdChannel(id: 2, data: planes[2]),
          PsdChannel(id: -1, data: planes[3]),
        ],
      ),
    ],
    mergedImage: planes,
    mergedTransparency: true,
  );
  await File(path).writeAsBytes(PsdCodec.encode(document), flush: true);
}
