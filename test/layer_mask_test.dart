import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Exercises the mask-header layout independently of optional mask parameters.
void main() {
  for (final PsdVersion version in PsdVersion.values) {
    for (final bool hasRealMask in <bool>[false, true]) {
      for (final bool hasParameters in <bool>[false, true]) {
        test('${version.name} mask: real=$hasRealMask parameters=$hasParameters', () {
          final PsdDocument source = _maskedDocument(version, hasRealMask: hasRealMask, hasParameters: hasParameters);
          final PsdLayer layer = PsdCodec.decode(PsdCodec.encode(source)).layers.single;
          final PsdLayerMask mask = layer.mask!;

          expect(mask.rectangle.width, 2);
          expect(mask.rectangle.height, 2);
          expect(mask.flags, hasParameters ? 0x10 : 0);
          expect(mask.data, orderedEquals(source.layers.single.mask!.data));
          expect(layer.channel(-2)!.data, orderedEquals(<int>[10, 20, 30, 40]));
          if (hasRealMask) {
            expect(mask.realFlags, 2);
            expect(mask.realDefaultColor, 255);
            expect(mask.realRectangle!.top, 1);
            expect(mask.realRectangle!.left, 1);
            expect(mask.realRectangle!.bottom, 3);
            expect(mask.realRectangle!.right, 2);
            expect(layer.channel(-3)!.data, orderedEquals(<int>[50, 60]));
          } else {
            expect(mask.realRectangle, isNull);
            expect(mask.realFlags, isNull);
            expect(mask.realDefaultColor, isNull);
          }
        });
      }
    }
  }
}

/// Supplies literal mask metadata so the encoder cannot hide a decoder bug.
PsdDocument _maskedDocument(PsdVersion version, {required bool hasRealMask, required bool hasParameters}) {
  const PsdRectangle rectangle = PsdRectangle(top: 0, left: 0, bottom: 2, right: 2);
  const PsdRectangle realRectangle = PsdRectangle(top: 1, left: 1, bottom: 3, right: 2);
  final PsBinaryWriter mask = PsBinaryWriter()
    ..writeInt32(0)
    ..writeInt32(0)
    ..writeInt32(2)
    ..writeInt32(2)
    ..writeUint8(0)
    ..writeUint8(hasParameters ? 0x10 : 0);
  if (hasRealMask) {
    mask
      ..writeUint8(2)
      ..writeUint8(255)
      ..writeInt32(1)
      ..writeInt32(1)
      ..writeInt32(3)
      ..writeInt32(2);
  }
  if (hasParameters) {
    mask
      ..writeUint8(0x0f)
      ..writeUint8(191)
      ..writeFloat64(3)
      ..writeUint8(204)
      ..writeFloat64(2);
  }
  while (mask.length % 4 != 0) {
    mask.writeUint8(0);
  }
  return PsdDocument(
    version: version,
    width: 2,
    height: 2,
    channels: 1,
    depth: 8,
    colorMode: PsdColorMode.grayscale,
    mergedImage: <Uint8List>[Uint8List(4)],
    layers: <PsdLayer>[
      PsdLayer(
        name: 'Mask parameters',
        rectangle: rectangle,
        channels: <PsdChannel>[
          PsdChannel(id: 0, data: Uint8List(4)),
          PsdChannel(id: -2, data: Uint8List.fromList(<int>[10, 20, 30, 40])),
          if (hasRealMask) PsdChannel(id: -3, data: Uint8List.fromList(<int>[50, 60])),
        ],
        mask: PsdLayerMask(
          rectangle: rectangle,
          defaultColor: 0,
          flags: hasParameters ? 0x10 : 0,
          data: mask.takeBytes(),
          realRectangle: hasRealMask ? realRectangle : null,
          realFlags: hasRealMask ? 2 : null,
          realDefaultColor: hasRealMask ? 255 : null,
        ),
      ),
    ],
  );
}
