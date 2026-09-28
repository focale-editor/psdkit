@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Checks a real Photoshop mask with negative, independently sized bounds.
void main() {
  test('round-trips the psd-tools painted-mask fixture byte for byte', () {
    final Uint8List bytes = base64Decode(File('test/fixtures/filter_effects_1.base64').readAsStringSync().replaceAll(RegExp(r'\s'), ''));
    final PsdFilterEffects effects = PsdFilterEffectsCodec.decode(bytes);
    final PsdFilterEffect effect = effects.effects.single;
    final PsdFilterEffectMask mask = effect.mask!;

    final Uint8List samples = mask.channel.decodePixels(width: mask.rectangle.width, height: mask.rectangle.height, depth: effect.depth);

    expect(effect.id, '5320dea1-2d9b-11e8-8261-8c5d7b8ff9e0');
    expect((effect.rectangle.top, effect.rectangle.left), (-4, -107));
    expect((mask.rectangle.top, mask.rectangle.left, mask.rectangle.bottom, mask.rectangle.right), (-610, -541, 842, 885));
    expect(samples.where((value) => value == 157).length, 753600);
    expect(samples.where((value) => value == 255).length, 1316952);
    expect(PsdFilterEffectsCodec.encode(effects), bytes);
  });
}
