@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Checks real Photoshop raster masks with density and feather parameters.
void main() {
  test('reads and rewrites psd-tools layer masks without confusing parameters with bounds', () {
    final Uint8List bytes = base64Decode(File('test/fixtures/layer_mask_data.base64').readAsStringSync().replaceAll(RegExp(r'\s'), ''));
    final PsdDocument document = PsdCodec.decode(bytes);
    final PsdLayer layer = document.layers.last;
    final PsdLayerMask mask = layer.mask!;

    expect(document.layers, hasLength(5));
    expect(mask.data, hasLength(56));
    expect(mask.flags, 0x18);
    expect(mask.realFlags, 0);
    expect(mask.realDefaultColor, 255);
    expect((mask.rectangle.top, mask.rectangle.left, mask.rectangle.bottom, mask.rectangle.right), (141, 12, 191, 188));
    final PsdRectangle real = mask.realRectangle!;
    expect((real.top, real.left, real.bottom, real.right), (146, 36, 186, 170));
    expect(layer.channel(-3)!.data, hasLength(40 * 134));

    final PsdDocument decoded = PsdCodec.decode(PsdCodec.encode(document));
    for (int index = 0; index < document.layers.length; index++) {
      final PsdLayer expected = document.layers[index];
      final PsdLayer actual = decoded.layers[index];
      expect(actual.mask?.data, expected.mask?.data);
      for (final PsdChannel channel in expected.channels) {
        expect(actual.channel(channel.id)!.data, channel.data);
      }
    }
  });
}
