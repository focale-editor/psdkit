import 'dart:convert';
import 'dart:io';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Checks adjustment layers saved by Photoshop against ag-psd's expected values.
void main() {
  final PsdDocument document = PsdCodec.decode(
    base64Decode(File('test/fixtures/adjustment_layers.base64').readAsStringSync().replaceAll(RegExp(r'\s'), '')),
    options: const PsdReadOptions(preserveSourceEncoding: true),
  );
  PsdLayer layer(String name) => document.layers.singleWhere((layer) => layer.name == name);

  test('reads modern brightness/contrast from the CgEd descriptor', () {
    final PsdBrightnessContrastAdjustment adjustment = layer('Brightness/Contrast 1').adjustment! as PsdBrightnessContrastAdjustment;

    expect(adjustment.brightness, 22);
    expect(adjustment.contrast, -7);
    expect(adjustment.mean, 127);
    expect(adjustment.useLegacy, isFalse);
    expect(adjustment.automatic, isFalse);
    expect((PsdAdjustmentCodec.decode(layer('Brightness/Contrast 1').taggedBlock('brit')!.data, key: 'brit') as PsdBrightnessContrastAdjustment).useLegacy, isTrue);
  });

  test('reads exposure as floating-point values and rewrites it identically', () {
    final PsdLayer exposureLayer = layer('Exposure 1');
    final PsdExposureAdjustment adjustment = exposureLayer.adjustment! as PsdExposureAdjustment;

    expect(adjustment.exposure, -2);
    expect(adjustment.offset, 0);
    expect(adjustment.gamma, 1);
    expect(PsdAdjustmentCodec.encode(adjustment), orderedEquals(exposureLayer.taggedBlock('expA')!.data));
  });

  test('reads the gradient map and rewrites it identically', () {
    final PsdLayer mapLayer = layer('Gradient Map 1');
    final PsdGradientMapAdjustment adjustment = mapLayer.adjustment! as PsdGradientMapAdjustment;

    expect(adjustment.name, r'$$$/DefaultGradient/VioletOrange=Violet, Orange');
    expect(adjustment.dither, isTrue);
    expect(adjustment.reverse, isFalse);
    expect(adjustment.colorStops.map((stop) => stop.location), <int>[0, 4096]);
    expect(adjustment.colorStops.first.components.take(3).map((component) => (component / 257).round()), <int>[41, 10, 89]);
    expect(adjustment.opacityStops.map((stop) => stop.opacity), <int>[255, 255]);
    expect(adjustment.smoothness, 4096);
    expect(PsdAdjustmentCodec.encode(adjustment), orderedEquals(mapLayer.taggedBlock('grdm')!.data));
  });

  test('decodes every adjustment layer without falling back to raw bytes', () {
    final List<PsdAdjustment> adjustments = [
      for (final PsdLayer layer in document.layers)
        if (layer.adjustment case final PsdAdjustment adjustment) adjustment,
    ];

    expect(adjustments, hasLength(16));
    expect(adjustments.whereType<PsdRawAdjustment>(), isEmpty);
  });
}
