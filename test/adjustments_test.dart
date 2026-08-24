import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Exercises Photoshop adjustment-layer encoding and decoding.
void main() {
  group('adjustments', () {
    test('round-trips the corpus curves variant byte for byte', () {
      final Uint8List bytes = Uint8List.fromList(<int>[
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
        4,
        0,
        0,
        0,
        0,
        0,
        59,
        0,
        70,
        0,
        193,
        0,
        189,
        0,
        255,
        0,
        255,
        67,
        114,
        118,
        32,
        0,
        4,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        4,
        0,
        0,
        0,
        0,
        0,
        59,
        0,
        70,
        0,
        193,
        0,
        189,
        0,
        255,
        0,
        255,
        0,
      ]);

      final PsdCurvesAdjustment curves = PsdAdjustmentCodec.decode(bytes, key: 'curv') as PsdCurvesAdjustment;

      expect(curves.curves.single.points[1].input, 70);
      expect(curves.curves.single.points[1].output, 59);
      expect(curves.extendedCurves.single.points, hasLength(4));
      expect(PsdAdjustmentCodec.encode(curves), orderedEquals(bytes));
    });

    test('round-trips color balance and preserves padding', () {
      final Uint8List bytes = Uint8List.fromList(<int>[
        0,
        20,
        0,
        34,
        0,
        43,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]);

      final PsdColorBalanceAdjustment balance = PsdAdjustmentCodec.decode(bytes, key: 'blnc') as PsdColorBalanceAdjustment;

      expect(balance.shadows.cyanRed, 20);
      expect(balance.shadows.magentaGreen, 34);
      expect(balance.shadows.yellowBlue, 43);
      expect(balance.preserveLuminosity, isTrue);
      expect(PsdAdjustmentCodec.encode(balance), orderedEquals(bytes));
    });

    test('round-trips levels, exposure, hue, mixer, filter, and selective color', () {
      final List<PsdAdjustment> adjustments = <PsdAdjustment>[
        PsdLevelsAdjustment.identity(),
        PsdExposureAdjustment(exposure: 1.25, offset: -0.125, gamma: 0.75),
        PsdHueSaturationAdjustment(
          master: const PsdHueSaturationValues(hue: 15, saturation: 20, lightness: -5),
          ranges: List<PsdHueSaturationRange>.filled(
            6,
            const PsdHueSaturationRange(boundaries: <int>[0, 30, 60, 90]),
          ),
        ),
        PsdChannelMixerAdjustment(
          outputs: const <PsdChannelMixerOutput>[
            PsdChannelMixerOutput(channels: <int>[100, 0, 0, 0]),
            PsdChannelMixerOutput(channels: <int>[0, 100, 0, 0]),
            PsdChannelMixerOutput(channels: <int>[0, 0, 100, 0]),
            PsdChannelMixerOutput(channels: <int>[0, 0, 0, 100]),
          ],
        ),
        PsdPhotoFilterAdjustment(colorData: Uint8List(12), density: 40),
        PsdSelectiveColorAdjustment(
          absolute: true,
          corrections: List<PsdSelectiveColorCorrection>.filled(10, const PsdSelectiveColorCorrection(cyan: -10, black: 5)),
        ),
      ];

      for (final PsdAdjustment adjustment in adjustments) {
        final Uint8List encoded = PsdAdjustmentCodec.encode(adjustment);
        final PsdAdjustment decoded = PsdAdjustmentCodec.decode(encoded, key: adjustment.blockKey);
        expect(PsdAdjustmentCodec.encode(decoded), orderedEquals(encoded), reason: adjustment.blockKey);
      }
    });

    test('round-trips descriptor adjustments and edits properties', () {
      final PsdDescriptorAdjustment source = PsdDescriptorAdjustment(
        blockKey: 'vibA',
        type: PsdAdjustmentType.vibrance,
        descriptor: const PsDescriptor(
          name: '',
          classId: 'vibA',
          items: <PsDescriptorItem>[PsDescriptorItem(key: 'vibrance', value: PsIntegerValue(value: 25))],
        ),
      );
      final PsdDescriptorAdjustment edited = source.withProperty('vibrance', const PsIntegerValue(value: 40));
      final Uint8List bytes = PsdAdjustmentCodec.encode(edited);
      final PsdDescriptorAdjustment decoded = PsdAdjustmentCodec.decode(bytes, key: 'vibA') as PsdDescriptorAdjustment;

      expect((decoded.descriptor.value('vibrance') as PsIntegerValue).value, 40);
      expect(PsdAdjustmentCodec.encode(decoded), orderedEquals(bytes));
    });

    test('attaches one adjustment and removes conflicting blocks', () {
      final PsdLayer layer = PsdLayer(
        rectangle: const PsdRectangle.fromSize(width: 1, height: 1),
        name: 'Adjustment',
        additionalInfo: <PsdTaggedBlock>[
          PsdTaggedBlock(key: 'nvrt', data: Uint8List(0)),
          PsdTaggedBlock(key: 'post', data: Uint8List.fromList(<int>[0, 4])),
          PsdTaggedBlock(key: 'lyid', data: Uint8List(4)),
        ],
      );

      final PsdLayer edited = layer.withAdjustment(
        PsdSingleValueAdjustment(type: PsdAdjustmentType.threshold, value: 128),
      );

      expect(edited.adjustment, isA<PsdSingleValueAdjustment>());
      expect((edited.adjustment as PsdSingleValueAdjustment).value, 128);
      expect(edited.additionalInfo.where((block) => psdAdjustmentKeys.contains(block.key)), hasLength(1));
      expect(edited.taggedBlock('lyid'), isNotNull);
    });
  });
}
