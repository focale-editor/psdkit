import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Exercises typed fill-layer paints and shape strokes.
void main() {
  group('PsdFillContent', () {
    test('creates and reads every paint kind through fill-layer blocks', () {
      final PsGradient gradient = PsGradient.custom(
        colorStops: <PsGradientColorStop>[
          PsGradientColorStop.create(color: PsColor.rgb(red: 0, green: 0, blue: 0), location: 0),
          PsGradientColorStop.create(color: PsColor.rgb(red: 255, green: 128, blue: 0), location: 4096),
        ],
      );
      final List<PsdFillContent> contents = <PsdFillContent>[
        PsdSolidColorFill.create(color: PsColor.rgb(red: 10, green: 20, blue: 30)),
        PsdGradientFill.create(gradient: gradient, style: PsGradientStyle.radial, angle: 45, scale: 80, reversed: true),
        PsdPatternFill.create(
          pattern: PsPatternReference.create(name: 'Dots', id: 'dots-id'),
          scale: 50,
          phaseX: 3,
        ),
      ];

      final List<PsdFillContent?> decoded = <PsdFillContent?>[for (final PsdFillContent content in contents) _roundTrip(_layer().withFill(content)).fill];

      expect(decoded.map((content) => content?.kind), <PsdFillKind>[PsdFillKind.solidColor, PsdFillKind.gradient, PsdFillKind.pattern]);
      final PsdSolidColorFill solid = decoded[0]! as PsdSolidColorFill;
      final PsdGradientFill gradientFill = decoded[1]! as PsdGradientFill;
      final PsdPatternFill pattern = decoded[2]! as PsdPatternFill;
      expect(solid.color?.green, 20);
      expect(gradientFill.style, PsGradientStyle.radial);
      expect(gradientFill.angle, 45);
      expect(gradientFill.scale, 80);
      expect(gradientFill.reversed, isTrue);
      expect(gradientFill.gradient?.colorStops.last.color?.green, 128);
      expect(gradientFill.offset?.horizontal?.unit, '#Prc');
      expect(pattern.pattern?.id, 'dots-id');
      expect(pattern.scale, 50);
      expect(pattern.phase?.horizontal?.value, 3);
    });

    test('exposes the paint of descriptor-backed fill adjustments only', () {
      final PsdDescriptorAdjustment fill = PsdSolidColorFill.create(color: PsColor.rgb(red: 1, green: 2, blue: 3)).toAdjustment();
      final PsdDescriptorAdjustment vibrance = PsdDescriptorAdjustment(
        blockKey: 'vibA',
        type: PsdAdjustmentType.vibrance,
        descriptor: const PsDescriptor(name: '', classId: 'null'),
      );

      expect(fill.blockKey, 'SoCo');
      expect(fill.fill, isA<PsdSolidColorFill>());
      expect(vibrance.fill, isNull);
    });

    test('prefers and updates the shape-fill block', () {
      final PsdFillContent red = PsdSolidColorFill.create(color: PsColor.rgb(red: 255, green: 0, blue: 0));
      final PsdFillContent blue = PsdSolidColorFill.create(color: PsColor.rgb(red: 0, green: 0, blue: 255));
      final PsdLayer layer = _layer(
        blocks: <PsdTaggedBlock>[
          PsdTaggedBlock(key: 'SoCo', data: PsdAdjustmentCodec.encode(red.toAdjustment())),
          blue.toShapeFillBlock(),
        ],
      );

      final PsdLayer recolored = layer.withFill(red);

      expect((layer.fill! as PsdSolidColorFill).color?.blue, 255);
      expect((recolored.fill! as PsdSolidColorFill).color?.red, 255);
      expect(recolored.additionalInfo.where((block) => block.key == 'vscg'), hasLength(1));
      expect(_layer().withFill(red).taggedBlock('vscg'), isNull);
    });

    test('ignores malformed shape-fill blocks', () {
      expect(PsdFillContent.tryDecodeShapeFill(Uint8List.fromList('XXXX'.codeUnits + <int>[0, 0, 0, 16])), isNull);
      expect(PsdFillContent.tryDecodeShapeFill(Uint8List(3)), isNull);
    });
  });

  group('PsdShapeStroke', () {
    test('creates a stroke whose settings survive a document round trip', () {
      final PsdShapeStroke stroke = PsdShapeStroke.create(
        content: PsdSolidColorFill.create(color: PsColor.rgb(red: 9, green: 8, blue: 7)),
        fillEnabled: false,
        width: 4,
        alignment: PsdShapeStrokeAlignment.outside,
        cap: PsdShapeStrokeCap.round,
        join: PsdShapeStrokeJoin.bevel,
        dashes: <double>[2, 1],
        opacity: 60,
      );

      final PsdShapeStroke? decoded = _roundTrip(_layer().withShapeStroke(stroke)).shapeStroke;

      expect(decoded?.strokeEnabled, isTrue);
      expect(decoded?.fillEnabled, isFalse);
      expect(decoded?.width, 4);
      expect(decoded?.alignment, PsdShapeStrokeAlignment.outside);
      expect(decoded?.cap, PsdShapeStrokeCap.round);
      expect(decoded?.join, PsdShapeStrokeJoin.bevel);
      expect(decoded?.dashes, <double>[2, 1]);
      expect(decoded?.opacity, 60);
      expect(decoded?.descriptor.objectValue('strokeStyleContent')?.classId, 'solidColorLayer');
      expect((decoded?.content as PsdSolidColorFill?)?.color?.red, 9);
    });

    test('nests gradient paints under the stroke-specific class', () {
      final PsdShapeStroke stroke = PsdShapeStroke.create(
        content: PsdGradientFill.create(
          gradient: PsGradient.custom(colorStops: <PsGradientColorStop>[PsGradientColorStop.create(color: PsColor.rgb(red: 0, green: 0, blue: 0), location: 0)]),
          angle: 30,
        ),
      );

      expect(stroke.content, isA<PsdGradientFill>());
      expect((stroke.content! as PsdGradientFill).angle, 30);
      expect(stroke.descriptor.objectValue('strokeStyleContent')?.classId, 'gradientLayer');
    });

    test('ignores malformed blocks and removes strokes', () {
      final PsdLayer layer = _layer(
        blocks: <PsdTaggedBlock>[
          PsdTaggedBlock(key: 'vstk', data: Uint8List.fromList(<int>[0, 0, 0, 16, 1])),
        ],
      );

      expect(layer.shapeStroke, isNull);
      expect(layer.withShapeStroke(null).taggedBlock('vstk'), isNull);
    });
  });
}

/// Creates a one-pixel layer carrying [blocks].
PsdLayer _layer({List<PsdTaggedBlock> blocks = const <PsdTaggedBlock>[]}) => PsdLayer(
  rectangle: const PsdRectangle.fromSize(width: 1, height: 1),
  name: 'Shape',
  channels: <PsdChannel>[for (int id = -1; id < 3; id++) PsdChannel(id: id, data: Uint8List(1))],
  additionalInfo: blocks,
);

/// Encodes and decodes [layer] inside a one-pixel RGB document.
PsdLayer _roundTrip(PsdLayer layer) => PsdCodec.decode(
  PsdCodec.encode(
    PsdDocument(
      width: 1,
      height: 1,
      channels: 3,
      depth: 8,
      colorMode: PsdColorMode.rgb,
      layers: <PsdLayer>[layer],
      mergedImage: <Uint8List>[for (int channel = 0; channel < 3; channel++) Uint8List(1)],
    ),
  ),
).layers.single;
