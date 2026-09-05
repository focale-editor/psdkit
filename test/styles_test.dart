import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

void main() {
  group('PsdStyleLibraryCodec', () {
    test('round-trips effects, blending options, patterns, and trailing data', () {
      final PsdStylePreset preset = PsdStylePreset.create(
        id: '11111111-2222-3333-4444-555555555555',
        name: 'Soft shadow',
        effects: PsdLayerEffects.create(
          effects: [
            PsdLayerEffect.create(
              type: PsdLayerEffectType.dropShadow,
              color: const PsdEffectColor(
                alpha: 255,
                red: 12,
                green: 34,
                blue: 56,
              ),
              opacity: 42,
              size: 8,
              distance: 4,
              angle: 120,
            ),
          ],
        ),
        blendingOptions: PsdLayerCompBlendOptions.create(
          fillOpacityPercent: 76,
          blendMode: 'Mltp',
        ),
      );
      final PsdStyleLibrary source = PsdStyleLibrary(
        patternsData: Uint8List.fromList([1, 2, 3]),
        styles: [preset],
        trailingData: Uint8List.fromList('8BIMphry'.codeUnits),
      );

      final Uint8List encoded = PsdStyleLibraryCodec.encode(source);
      final PsdStyleLibrary decoded = PsdStyleLibraryCodec.decode(encoded);

      expect(PsdStyleLibraryCodec.encode(decoded), orderedEquals(encoded));
      expect(decoded.patternsData, orderedEquals([1, 2, 3]));
      expect(decoded.trailingData, orderedEquals('8BIMphry'.codeUnits));
      expect(decoded.styles.single.name, 'Soft shadow');
      expect(decoded.styles.single.id, preset.id);
      expect(decoded.styles.single.effects!.effects.single.type, PsdLayerEffectType.dropShadow);
      expect(decoded.styles.single.blendingOptions!.fillOpacityPercent, 76);
      expect(decoded.styles.single.blendingOptions!.blendMode, 'Mltp');
    });

    test('resolves localized style names', () {
      final PsdStylePreset preset = PsdStylePreset(
        identityDescriptor: const PsDescriptor(
          name: '',
          classId: 'null',
          items: [
            PsDescriptorItem(
              key: 'Nm  ',
              value: PsStringValue(value: r'$$$/Styles/DropShadow=Drop Shadow'),
            ),
            PsDescriptorItem(
              key: 'Idnt',
              value: PsStringValue(value: 'id'),
            ),
          ],
        ),
        styleDescriptor: const PsDescriptor(name: '', classId: 'Styl'),
      );

      expect(preset.name, 'Drop Shadow');
    });

    test('rejects unsafe style counts', () {
      final PsBinaryWriter writer = PsBinaryWriter()
        ..writeUint16(2)
        ..writeString('8BSL')
        ..writeUint16(3)
        ..writeUint32(0)
        ..writeUint32(PsdStyleLibraryCodec.maximumStyleCount + 1);

      expect(
        () => PsdStyleLibraryCodec.decode(writer.takeBytes()),
        throwsA(isA<PsFormatException>()),
      );
    });
  });
}
