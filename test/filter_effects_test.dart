import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Verifies lazy plane decoding, strict framing, and per-instance association.
void main() {
  for (final PsdCompression compression in PsdCompression.values) {
    for (final int depth in [8, 16, 32]) {
      test('round-trips $compression at $depth bits with independent mask bounds', () {
        final Uint8List pixels = Uint8List.fromList(List.generate(6 * depth ~/ 8, (index) => index * 7 % 256));
        final PsdFilterEffectChannel channel = PsdFilterEffectChannel.fromPixels(pixels: pixels, width: 3, height: 2, depth: depth, compression: compression);
        final PsdFilterEffects source = PsdFilterEffects(
          effects: [_effect(channel: channel, depth: depth)],
        );
        final Uint8List bytes = PsdFilterEffectsCodec.encode(source);

        final PsdFilterEffects decoded = PsdFilterEffectsCodec.decode(bytes);

        final PsdFilterEffect effect = decoded.effects.single;
        expect(effect.channels.length, 26);
        expect(effect.channels[1], isNull);
        expect(effect.channels[24]?.compression, isNull);
        expect(effect.channels[24], isNotNull);
        expect(effect.mask?.rectangle.top, -2);
        expect(effect.mask!.channel.decodePixels(width: 3, height: 2, depth: depth), pixels);
        expect(effect.channels.first!.decodePixels(width: 3, height: 2, depth: depth), pixels);
        expect(PsdFilterEffectsCodec.encode(decoded), bytes);
      });
    }
  }

  test('PackBits uses wide row lengths in both containers', () {
    final PsdFilterEffectChannel channel = PsdFilterEffectChannel.fromPixels(pixels: Uint8List.fromList([0, 128, 255]), width: 3, height: 1);
    expect(channel.data.take(4), [0, 0, 0, 4]);
  });

  test('keeps absent mask records and opaque extension bytes', () {
    final PsdFilterEffect effect = PsdFilterEffect(
      id: 'instance',
      rectangle: const PsdRectangle.fromSize(width: 1, height: 1),
      depth: 8,
      channels: [null, null],
      maskRecordPresent: false,
      bodyTrailingData: Uint8List.fromList([3, 2, 1]),
    );
    final Uint8List bytes = PsdFilterEffectsCodec.encode(PsdFilterEffects(version: 1, effects: [effect]));
    final PsdFilterEffects decoded = PsdFilterEffectsCodec.decode(bytes);
    expect(decoded.effects.single.maskRecordPresent, isFalse);
    expect(decoded.effects.single.bodyTrailingData, [3, 2, 1]);
    expect(PsdFilterEffectsCodec.encode(decoded), bytes);
  });

  test('unknown compression stays opaque and cannot be inflated', () {
    final PsdFilterEffectChannel channel = PsdFilterEffectChannel(compression: 65000, data: Uint8List.fromList([1, 2]));
    final Uint8List bytes = PsdFilterEffectsCodec.encode(PsdFilterEffects(effects: [_effect(channel: channel)]));
    final PsdFilterEffects decoded = PsdFilterEffectsCodec.decode(bytes);
    expect(PsdFilterEffectsCodec.encode(decoded), bytes);
    expect(() => decoded.effects.single.channels.first!.decodePixels(width: 3, height: 2, depth: 8), throwsA(isA<PsFormatException>()));
  });

  test('rejects truncations and oversized nested lengths without allocating', () {
    final Uint8List bytes = PsdFilterEffectsCodec.encode(PsdFilterEffects(effects: [_effect(channel: _channel())]));
    for (int length = 0; length < bytes.length; length++) {
      // A version header alone is a valid empty collection.
      if (length == 4) {
        continue;
      }
      expect(() => PsdFilterEffectsCodec.decode(Uint8List.sublistView(bytes, 0, length)), throwsA(isA<PsFormatException>()), reason: '$length bytes');
    }
    ByteData.sublistView(bytes).setUint32(4, 0xffffffff);
    expect(() => PsdFilterEffectsCodec.decode(bytes), throwsA(isA<PsFormatException>()));
  });

  test('enforces byte, record, and decoded-plane admission limits', () {
    final PsdFilterEffects source = PsdFilterEffects(effects: [_effect(channel: _channel())]);
    final Uint8List bytes = PsdFilterEffectsCodec.encode(source);
    expect(() => PsdFilterEffectsCodec.decode(bytes, maxEffects: 0), throwsA(isA<PsFormatException>()));
    expect(() => PsdFilterEffectsCodec.decode(bytes, maxEncodedBytes: bytes.length - 1), throwsA(isA<PsFormatException>()));
    expect(() => PsdFilterEffectsCodec.encode(source, maxEncodedBytes: bytes.length - 1), throwsA(isA<PsWriteException>()));
    expect(() => _channel().decodePixels(width: 3, height: 2, depth: 8, maxDecodedBytes: 5), throwsA(isA<PsFormatException>()));
    expect(() => _channel().decodePixels(width: 300000, height: 300000, depth: 32), throwsA(isA<PsFormatException>()));
    expect(() => _channel().decodePixels(width: -1, height: 2, depth: 8), throwsA(isA<PsFormatException>()));
    expect(() => _channel().decodePixels(width: 3, height: 2, depth: 12), throwsA(isA<PsFormatException>()));
  });

  for (final PsdVersion version in PsdVersion.values) {
    test('$version resolves caches by placement, not shared source, through the container', () {
      final PsdLayer first = _layer(id: 'first');
      final PsdLayer second = _layer(id: 'second');
      final PsdDocument document =
          PsdDocument(
            version: version,
            width: 1,
            height: 1,
            channels: 3,
            depth: 8,
            colorMode: PsdColorMode.rgb,
            layers: [first, second],
            mergedImage: [Uint8List(1), Uint8List(1), Uint8List(1)],
          ).withFilterEffects(
            PsdFilterEffects(
              effects: [
                _effect(id: 'first', channel: _channel()),
                _effect(id: 'second', channel: _channel()),
              ],
            ),
          );

      final PsdDocument decoded = PsdCodec.decode(PsdCodec.encode(document));

      expect(decoded.filterEffectFor(decoded.layers.first)?.id, 'first');
      expect(decoded.filterEffectFor(decoded.layers.last)?.id, 'second');
      final PsdDocument ambiguous = document.withFilterEffects(
        PsdFilterEffects(
          effects: [
            _effect(id: 'first', channel: _channel()),
            _effect(id: 'first', channel: _channel()),
          ],
        ),
      );
      expect(ambiguous.filterEffectFor(first), isNull);
    });
  }
}

/// Supplies a small plane with dark, gray, white, and intermediate samples.
PsdFilterEffectChannel _channel() => PsdFilterEffectChannel.fromPixels(pixels: Uint8List.fromList([0, 128, 255, 32, 64, 192]), width: 3, height: 2);

/// Creates sparse Photoshop RGB cache slots and an independently offset mask.
PsdFilterEffect _effect({String id = 'instance', required PsdFilterEffectChannel channel, int depth = 8}) => PsdFilterEffect(
  id: id,
  rectangle: const PsdRectangle.fromSize(width: 3, height: 2),
  depth: depth,
  channels: [
    channel,
    ...List<PsdFilterEffectChannel?>.filled(23, null),
    PsdFilterEffectChannel(compression: null, data: Uint8List(0)),
    channel,
  ],
  mask: PsdFilterEffectMask(rectangle: const PsdRectangle(top: -2, left: 4, bottom: 0, right: 7), channel: channel),
);

/// Creates two independently identified instances pointing at the same source.
PsdLayer _layer({required String id}) => PsdLayer(rectangle: const PsdRectangle.fromSize(width: 0, height: 0), name: id, channels: const []).withSmartObject(
  PsdDescriptorSmartObject(
    descriptor: PsDescriptor(
      name: '',
      classId: 'null',
      items: [
        const PsDescriptorItem(
          key: 'Idnt',
          value: PsStringValue(value: 'source'),
        ),
        PsDescriptorItem(
          key: 'placed',
          value: PsStringValue(value: '$id\u0000'),
        ),
      ],
    ),
  ),
);
