import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Exercises modern and legacy Photoshop layer effects.
void main() {
  group('PsdLayerEffects', () {
    test('creates and round-trips modern effects, gradients, and repetitions', () {
      const PsdEffectGradient gradient = PsdEffectGradient(
        name: 'Focale',
        colors: <PsdGradientColorStop>[
          PsdGradientColorStop(color: PsdEffectColor(alpha: 255, red: 10, green: 20, blue: 30), location: 0),
          PsdGradientColorStop(color: PsdEffectColor(alpha: 255, red: 200, green: 210, blue: 220), location: 4096),
        ],
        opacities: <PsdGradientOpacityStop>[
          PsdGradientOpacityStop(opacity: 100, location: 0),
          PsdGradientOpacityStop(opacity: 50, location: 4096),
        ],
      );
      final PsdLayerEffects source = PsdLayerEffects.create(
        scale: 125,
        effects: <PsdLayerEffect>[
          PsdLayerEffect.create(
            type: PsdLayerEffectType.dropShadow,
            blendMode: 'Mltp',
            opacity: 65,
            size: 12,
            distance: 8,
            angle: 120,
          ),
          PsdLayerEffect.create(type: PsdLayerEffectType.dropShadow, opacity: 20, size: 3),
          PsdLayerEffect.create(
            type: PsdLayerEffectType.stroke,
            color: const PsdEffectColor(alpha: 255, red: 1, green: 2, blue: 3),
            size: 4,
            strokePosition: PsdStrokePosition.inside,
          ),
          PsdLayerEffect.create(
            type: PsdLayerEffectType.gradientOverlay,
            gradient: gradient,
            gradientStyle: PsdGradientStyle.radial,
            angle: -45,
          ),
          PsdLayerEffect.create(
            type: PsdLayerEffectType.patternOverlay,
            pattern: const PsdEffectPattern(name: 'Dots', id: 'pattern-uuid'),
          ),
        ],
      );

      final Uint8List encoded = PsdLayerEffectsCodec.encode(source);
      final PsdLayerEffects decoded = PsdLayerEffectsCodec.decode(encoded);

      expect(PsdLayerEffectsCodec.encode(decoded), orderedEquals(encoded));
      expect(decoded.scale, 125);
      expect(decoded.effects.where((effect) => effect.type == PsdLayerEffectType.dropShadow), hasLength(2));
      final PsdLayerEffect stroke = decoded.effects.singleWhere((effect) => effect.type == PsdLayerEffectType.stroke);
      expect(stroke.strokePosition, PsdStrokePosition.inside);
      expect(stroke.size, 4);
      expect(stroke.color?.argb, 0xff010203);
      final PsdLayerEffect gradientEffect = decoded.effects.singleWhere((effect) => effect.type == PsdLayerEffectType.gradientOverlay);
      expect(gradientEffect.gradientStyle, PsdGradientStyle.radial);
      expect(gradientEffect.gradient?.name, 'Focale');
      expect(gradientEffect.gradient?.colors, hasLength(2));
      final PsdLayerEffect pattern = decoded.effects.singleWhere((effect) => effect.type == PsdLayerEffectType.patternOverlay);
      expect(pattern.pattern?.id, 'pattern-uuid');
    });

    test('edits known properties while retaining unknown descriptor items', () {
      const PsdLayerEffect source = PsdLayerEffect(
        type: PsdLayerEffectType.outerGlow,
        descriptor: PsDescriptor(
          name: '\u0000',
          classId: 'OrGl',
          items: <PsDescriptorItem>[
            PsDescriptorItem(key: 'enab', value: PsBooleanValue(value: true)),
            PsDescriptorItem(
              key: 'Opct',
              value: PsUnitFloatValue(unit: '#Prc', value: 10),
            ),
            PsDescriptorItem(
              key: 'futureAdobeKey',
              value: PsStringValue(value: 'retained'),
            ),
          ],
        ),
      );

      final PsdLayerEffect edited = source.withOpacity(72.5).withColor(const PsdEffectColor(alpha: 255, red: 4, green: 5, blue: 6));

      expect(edited.opacity, 72.5);
      expect(edited.color?.argb, 0xff040506);
      expect((edited.descriptor.value('futureAdobeKey')! as PsStringValue).value, 'retained');
    });

    test('decodes legacy lrFX and converts edits to modern lfx2', () {
      final Uint8List bytes = _legacySolidFill();

      final PsdLayerEffects legacy = PsdLayerEffectsCodec.decode(bytes, key: 'lrFX');

      expect(legacy.blockKey, 'lrFX');
      expect(PsdLayerEffectsCodec.encode(legacy), orderedEquals(bytes));
      expect(legacy.effects.single.type, PsdLayerEffectType.colorOverlay);
      expect(legacy.effects.single.color?.argb, 0xffff0000);
      expect(legacy.effects.single.opacity, closeTo(50.196, 0.001));

      final PsdLayerEffects edited = legacy.withEffects(<PsdLayerEffect>[legacy.effects.single.withOpacity(80)]);
      expect(edited.blockKey, 'lfx2');
      expect(PsdLayerEffectsCodec.decode(PsdLayerEffectsCodec.encode(edited)).effects.single.opacity, 80);
    });

    test('attaches effects and removes conflicting legacy blocks', () {
      final PsdLayer layer = PsdLayer(
        rectangle: const PsdRectangle(top: 0, left: 0, bottom: 1, right: 1),
        name: 'Effect',
        additionalInfo: <PsdTaggedBlock>[
          PsdTaggedBlock(key: 'lrFX', data: _legacySolidFill()),
          PsdTaggedBlock(key: 'cust', data: Uint8List.fromList(<int>[1, 2, 3])),
        ],
      );
      final PsdLayerEffects effects = PsdLayerEffects.create(
        effects: <PsdLayerEffect>[PsdLayerEffect.create(type: PsdLayerEffectType.colorOverlay)],
      );

      final PsdLayer edited = layer.withEffects(effects);

      expect(edited.taggedBlock('lrFX'), isNull);
      expect(edited.taggedBlock('lfx2'), isNotNull);
      expect(edited.taggedBlock('cust')?.data, orderedEquals(<int>[1, 2, 3]));
      expect(edited.effects?.effects.single.type, PsdLayerEffectType.colorOverlay);
    });
  });
}

/// Builds a complete legacy solid-fill effects payload.
Uint8List _legacySolidFill() {
  final Uint8List common = _bytes(<Uint8List>[
    _uint32(0),
    Uint8List.fromList(<int>[1]),
    _uint16(0),
  ]);
  final Uint8List fill = _bytes(<Uint8List>[
    _uint32(0),
    Uint8List.fromList('8BIMnorm'.codeUnits),
    _legacyRgb(255, 0, 0),
    Uint8List.fromList(<int>[128, 1]),
    _legacyRgb(255, 0, 0),
  ]);
  return _bytes(<Uint8List>[
    _uint16(0),
    _uint16(2),
    _legacyEntry('cmnS', common),
    _legacyEntry('sofi', fill),
  ]);
}

/// Wraps [value] in one legacy effect entry identified by [key].
Uint8List _legacyEntry(String key, Uint8List value) => _bytes(<Uint8List>[
  Uint8List.fromList('8BIM$key'.codeUnits),
  _uint32(value.length),
  value,
]);

/// Encodes one legacy 16-bit RGB color record.
Uint8List _legacyRgb(int red, int green, int blue) => _bytes(<Uint8List>[
  _uint16(0),
  _uint16(red * 257),
  _uint16(green * 257),
  _uint16(blue * 257),
  _uint16(0),
]);

/// Concatenates binary [parts] without copying intermediate results.
Uint8List _bytes(List<Uint8List> parts) {
  final BytesBuilder output = BytesBuilder(copy: false);
  parts.forEach(output.add);
  return output.takeBytes();
}

/// Encodes [value] as one big-endian unsigned 16-bit integer.
Uint8List _uint16(int value) => (ByteData(2)..setUint16(0, value)).buffer.asUint8List();

/// Encodes [value] as one big-endian unsigned 32-bit integer.
Uint8List _uint32(int value) => (ByteData(4)..setUint32(0, value)).buffer.asUint8List();
