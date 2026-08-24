import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:psdkit/src/compression.dart';
import 'package:test/test.dart';

/// Exercises complete PSD encoding, decoding, pixels, and limits.
void main() {
  group('PsdCodec', () {
    for (final PsdCompression compression in PsdCompression.values) {
      test('round-trips an 8-bit layered PSD with ${compression.name}', () {
        final PsdDocument source = _document(compression: compression);

        final Uint8List encoded = PsdCodec.encode(source);
        final PsdDocument decoded = PsdCodec.decode(encoded);

        expect(String.fromCharCodes(encoded.take(4)), '8BPS');
        expect(decoded.version, PsdVersion.psd);
        expect(decoded.width, 3);
        expect(decoded.height, 2);
        expect(decoded.colorMode, PsdColorMode.rgb);
        expect(decoded.mergedImageCompression, compression);
        expect(decoded.mergedImage[0], orderedEquals(source.mergedImage[0]));
        expect(decoded.mergedImage[1], orderedEquals(source.mergedImage[1]));
        expect(decoded.mergedImage[2], orderedEquals(source.mergedImage[2]));
        expect(decoded.imageResources.single.id, 1060);
        expect(decoded.imageResources.single.name, 'X');
        expect(decoded.imageResources.single.data, orderedEquals(<int>[1, 2, 3]));
        expect(decoded.globalLayerMaskData, orderedEquals(<int>[5, 4, 3, 2]));
        expect(decoded.layers, hasLength(1));
        expect(decoded.layers.single.name, 'Été 🌴');
        expect(decoded.layers.single.id, 42);
        expect(decoded.layers.single.sectionType, PsdSectionType.openFolder);
        expect(decoded.layers.single.channel(-1)?.data, orderedEquals(<int>[255, 128, 64, 32, 16, 0]));
        expect(decoded.layers.single.taggedBlock('cust')?.data, orderedEquals(<int>[9, 8, 7]));
      });
    }

    test('round-trips PSB 64-bit lengths and 16-bit prediction', () {
      final List<Uint8List> channels = <Uint8List>[
        _uint16(<int>[0, 1, 255, 256, 32768, 65535]),
        _uint16(<int>[65535, 32768, 256, 255, 1, 0]),
        _uint16(<int>[123, 456, 789, 1024, 4096, 32000]),
      ];
      final PsdDocument source = PsdDocument(
        version: PsdVersion.psb,
        width: 3,
        height: 2,
        channels: 3,
        depth: 16,
        colorMode: PsdColorMode.rgb,
        mergedImage: channels,
        mergedImageCompression: PsdCompression.zipPrediction,
        additionalLayerInfo: <PsdTaggedBlock>[
          PsdTaggedBlock(key: 'Layr', data: Uint8List.fromList(<int>[1, 2, 3])),
        ],
      );

      final PsdDocument decoded = PsdCodec.decode(PsdCodec.encode(source));

      expect(decoded.version, PsdVersion.psb);
      expect(decoded.depth, 16);
      for (int index = 0; index < channels.length; index++) {
        expect(decoded.mergedImage[index], orderedEquals(channels[index]));
      }
      expect(decoded.additionalLayerInfo.single.key, 'Layr');
      expect(decoded.additionalLayerInfo.single.data, orderedEquals(<int>[1, 2, 3]));
    });

    test('regenerates depth-specific alternative layer information', () {
      final List<Uint8List> merged = <Uint8List>[
        _uint16(<int>[1, 2]),
        _uint16(<int>[3, 4]),
        _uint16(<int>[5, 6]),
      ];
      final PsdDocument source = PsdDocument(
        width: 2,
        height: 1,
        channels: 3,
        depth: 16,
        colorMode: PsdColorMode.rgb,
        layers: <PsdLayer>[
          PsdLayer(
            rectangle: const PsdRectangle.fromSize(width: 2, height: 1),
            name: '16-bit layer',
            channels: <PsdChannel>[
              PsdChannel(id: 0, data: _uint16(<int>[10, 20])),
              PsdChannel(id: 1, data: _uint16(<int>[30, 40])),
              PsdChannel(id: 2, data: _uint16(<int>[50, 60])),
              PsdChannel(id: -1, data: _uint16(<int>[65535, 32768])),
            ],
          ),
        ],
        mergedImage: merged,
        additionalLayerInfo: <PsdTaggedBlock>[
          PsdTaggedBlock(key: 'Lr16', data: Uint8List.fromList(<int>[1, 2, 3])),
          PsdTaggedBlock(key: 'cust', data: Uint8List.fromList(<int>[9, 8, 7])),
        ],
      );

      final PsdDocument decoded = PsdCodec.decode(PsdCodec.encode(source));

      expect(decoded.layers, hasLength(1));
      expect(decoded.layers.single.name, '16-bit layer');
      expect(decoded.layers.single.channel(-1)?.data, orderedEquals(_uint16(<int>[65535, 32768])));
      expect(decoded.additionalLayerInfo.map((block) => block.key), orderedEquals(<String>['Lr16', 'cust']));
      expect(decoded.additionalLayerInfo.first.data, isNot(orderedEquals(<int>[1, 2, 3])));

      final PsdDocument withoutLayers = PsdDocument(
        width: 2,
        height: 1,
        channels: 3,
        depth: 16,
        colorMode: PsdColorMode.rgb,
        mergedImage: merged,
        additionalLayerInfo: decoded.additionalLayerInfo,
      );
      final PsdDocument emptyDecoded = PsdCodec.decode(PsdCodec.encode(withoutLayers));
      expect(emptyDecoded.layers, isEmpty);
      expect(emptyDecoded.additionalLayerInfo.map((block) => block.key), orderedEquals(<String>['cust']));
    });

    test('rejects malformed and oversized input', () {
      final Uint8List encoded = PsdCodec.encode(_document());
      encoded[0] = 0;
      expect(() => PsdCodec.decode(encoded), throwsA(isA<PsFormatException>()));

      expect(
        () => PsdCodec.decode(PsdCodec.encode(_document()), options: const PsdReadOptions(maxPixels: 2)),
        throwsA(isA<PsFormatException>()),
      );
    });

    test('bounds ZIP expansion before accepting decoded channel bytes', () {
      final Uint8List compressed = Uint8List.fromList(zlib.encode(Uint8List(1024 * 1024)));

      expect(
        () => decodePsdChannel(
          compression: PsdCompression.zip,
          payload: compressed,
          width: 1,
          height: 1,
          depth: 8,
          wideRowLengths: false,
          maxDecodedBytes: 1,
        ),
        throwsA(isA<PsFormatException>()),
      );
    });

    test('uses Photoshop byte-plane prediction for 32-bit channels', () {
      final Uint8List samples = Uint8List.fromList(<int>[
        0x3f,
        0x80,
        0x00,
        0x00,
        0x40,
        0x00,
        0x00,
        0x00,
        0x40,
        0x40,
        0x00,
        0x00,
      ]);
      final Uint8List predicted = Uint8List.fromList(<int>[
        0x3f,
        0x01,
        0x00,
        0x40,
        0x80,
        0x40,
        0xc0,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);

      final Uint8List encoded = encodePsdChannel(
        compression: PsdCompression.zipPrediction,
        data: samples,
        width: 3,
        height: 1,
        depth: 32,
        wideRowLengths: false,
      );
      expect(zlib.decode(encoded), orderedEquals(predicted));
      expect(
        decodePsdChannel(
          compression: PsdCompression.zipPrediction,
          payload: Uint8List.fromList(zlib.encode(predicted)),
          width: 3,
          height: 1,
          depth: 32,
          wideRowLengths: false,
          maxDecodedBytes: samples.length,
        ),
        orderedEquals(samples),
      );
    });

    test('splits PackBits literals at exactly 128 bytes', () {
      final Uint8List samples = Uint8List.fromList(<int>[
        for (int index = 0; index < 513; index++) (index ~/ 2) & 0xff,
      ]);

      final Uint8List encoded = encodePsdChannel(
        compression: PsdCompression.rle,
        data: samples,
        width: samples.length,
        height: 1,
        depth: 8,
        wideRowLengths: false,
      );
      expect(
        decodePsdChannel(
          compression: PsdCompression.rle,
          payload: encoded,
          width: samples.length,
          height: 1,
          depth: 8,
          wideRowLengths: false,
          maxDecodedBytes: samples.length,
        ),
        orderedEquals(samples),
      );
    });

    test('round-trips compression boundaries at every sample depth', () {
      final Random random = Random(42);
      for (final int depth in <int>[1, 8, 16, 32]) {
        for (final int width in <int>[1, 2, 127, 128, 129, 257]) {
          final Uint8List samples = Uint8List.fromList(<int>[
            for (int index = 0; index < psdRowBytes(width, depth) * 3; index++) random.nextInt(256),
          ]);
          for (final PsdCompression compression in PsdCompression.values) {
            if (depth == 1 && compression == PsdCompression.zipPrediction) {
              continue;
            }
            final Uint8List encoded = encodePsdChannel(
              compression: compression,
              data: samples,
              width: width,
              height: 3,
              depth: depth,
              wideRowLengths: false,
            );
            expect(
              decodePsdChannel(
                compression: compression,
                payload: encoded,
                width: width,
                height: 3,
                depth: depth,
                wideRowLengths: false,
                maxDecodedBytes: samples.length,
              ),
              orderedEquals(samples),
              reason: '$compression at $width x 3 x $depth-bit',
            );
          }
        }
      }
    });
  });

  group('PsdPixels', () {
    test('converts merged RGB and layer alpha to RGBA', () {
      final PsdDocument document = _document();

      final PsdRgbaImage merged = PsdPixels.decodeMerged(document);
      final PsdRgbaImage layer = PsdPixels.decodeLayer(document, document.layers.single);

      expect(merged.bytes.take(8), orderedEquals(<int>[1, 7, 13, 255, 2, 8, 14, 255]));
      expect(layer.bytes.take(8), orderedEquals(<int>[10, 70, 130, 255, 20, 80, 140, 128]));
      expect(PsdPixels.encodeRgb(layer)[3], orderedEquals(<int>[255, 128, 64, 32, 16, 0]));
    });

    test('handles indexed palettes and padded bitmap rows', () {
      final Uint8List palette = Uint8List(768)
        ..[2] = 10
        ..[258] = 20
        ..[514] = 30;
      final PsdDocument indexed = PsdDocument(
        width: 1,
        height: 1,
        channels: 1,
        depth: 8,
        colorMode: PsdColorMode.indexed,
        colorModeData: palette,
        mergedImage: <Uint8List>[
          Uint8List.fromList(<int>[2]),
        ],
      );
      final PsdDocument bitmap = PsdDocument(
        width: 3,
        height: 2,
        channels: 1,
        depth: 1,
        colorMode: PsdColorMode.bitmap,
        mergedImage: <Uint8List>[
          Uint8List.fromList(<int>[0x40, 0xa0]),
        ],
      );

      expect(PsdPixels.decodeMerged(indexed).bytes, orderedEquals(<int>[10, 20, 30, 255]));
      expect(
        PsdPixels.decodeMerged(bitmap).bytes.whereIndexed((index, value) => index % 4 == 0),
        orderedEquals(<int>[255, 0, 255, 0, 255, 0]),
      );
    });

    test('converts Photoshop-inverted CMYK channels', () {
      final PsdDocument document = PsdDocument(
        width: 1,
        height: 1,
        channels: 4,
        depth: 8,
        colorMode: PsdColorMode.cmyk,
        mergedImage: <Uint8List>[
          Uint8List.fromList(<int>[255]),
          Uint8List.fromList(<int>[0]),
          Uint8List.fromList(<int>[0]),
          Uint8List.fromList(<int>[255]),
        ],
      );

      expect(PsdPixels.decodeMerged(document).bytes, orderedEquals(<int>[255, 0, 0, 255]));
    });
  });
}

/// Builds the representative layered document shared by codec tests.
PsdDocument _document({PsdCompression compression = PsdCompression.rle}) {
  const PsdRectangle rectangle = PsdRectangle(top: -1, left: -2, bottom: 1, right: 1);
  return PsdDocument(
    width: 3,
    height: 2,
    channels: 3,
    depth: 8,
    colorMode: PsdColorMode.rgb,
    imageResources: <PsdImageResource>[
      PsdImageResource(id: 1060, name: 'X', data: Uint8List.fromList(<int>[1, 2, 3])),
    ],
    layers: <PsdLayer>[
      PsdLayer(
        rectangle: rectangle,
        name: 'Été 🌴',
        channels: <PsdChannel>[
          PsdChannel(id: 0, data: Uint8List.fromList(<int>[10, 20, 30, 40, 50, 60]), compression: compression),
          PsdChannel(id: 1, data: Uint8List.fromList(<int>[70, 80, 90, 100, 110, 120]), compression: compression),
          PsdChannel(id: 2, data: Uint8List.fromList(<int>[130, 140, 150, 160, 170, 180]), compression: compression),
          PsdChannel(id: -1, data: Uint8List.fromList(<int>[255, 128, 64, 32, 16, 0]), compression: compression),
        ],
        opacity: 204,
        additionalInfo: <PsdTaggedBlock>[
          PsdTaggedBlock(key: 'lyid', data: _uint32(42)),
          PsdTaggedBlock(key: 'lsct', data: _uint32(PsdSectionType.openFolder.code)),
          PsdTaggedBlock(key: 'cust', data: Uint8List.fromList(<int>[9, 8, 7])),
        ],
      ),
    ],
    mergedImage: <Uint8List>[
      Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6]),
      Uint8List.fromList(<int>[7, 8, 9, 10, 11, 12]),
      Uint8List.fromList(<int>[13, 14, 15, 16, 17, 18]),
    ],
    mergedImageCompression: compression,
    globalLayerMaskData: Uint8List.fromList(<int>[5, 4, 3, 2]),
  );
}

/// Encodes [value] as one big-endian unsigned 32-bit integer.
Uint8List _uint32(int value) {
  final ByteData data = ByteData(4)..setUint32(0, value);
  return data.buffer.asUint8List();
}

/// Encodes [values] as big-endian unsigned 16-bit integers.
Uint8List _uint16(List<int> values) {
  final ByteData data = ByteData(values.length * 2);
  for (int index = 0; index < values.length; index++) {
    data.setUint16(index * 2, values[index]);
  }
  return data.buffer.asUint8List();
}

/// Adds index-aware filtering to test iterables.
extension<T> on Iterable<T> {
  /// Returns values for which [predicate] accepts both index and value.
  Iterable<T> whereIndexed(bool Function(int index, T value) predicate) sync* {
    int index = 0;
    for (final T value in this) {
      if (predicate(index++, value)) {
        yield value;
      }
    }
  }
}
