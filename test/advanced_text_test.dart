@TestOn('vm')
library;

import 'dart:io';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Exercises producer geometry and complete generated text-engine ownership.
void main() {
  test('reads Photoshop circle and wave frames in text-local coordinates', () {
    for (final String name in ['path-circle', 'path-wave-open']) {
      final PsdDocument source = PsdCodec.decode(File('test/corpus/photocraft/photoshop/text/$name.psd').readAsBytesSync());
      final int index = source.layers.indexWhere((layer) => layer.typeTool != null);
      final PsdTextContent content = source.textContentFor(source.layers[index])!;
      expect(content.path, isNotNull);
      expect(content.hasUnsupportedGeometry, isFalse);
      expect(content.path!.controlPoints.length % 8, 0);
      final PsdDocument edited = PsdCodec.decode(PsdCodec.encode(source.withTextContent(index, content.copyWith(text: 'Edited 😀'))));
      expect(edited.textContentFor(edited.layers[index])!.text, 'Edited 😀');
      expect(edited.textContentFor(edited.layers[index])!.path!.controlPoints, content.path!.controlPoints);
    }
  });

  test('builds independently indexed path, list and ordinary text objects', () {
    final PsdGlobalTextBuilder builder = PsdGlobalTextBuilder();
    final List<PsdTypeTool> tools = [];
    for (int i = 0; i < 3; i++) {
      final String text = i == 1 ? 'One😀\rTwo' : 'Text $i';
      final PsdTextContent content = PsdTextContent(
        text: text,
        orientation: PsdTextOrientation.horizontal,
        path: i == 2 ? PsdTextPath(controlPoints: [0, 30, 20, 0, 70, 0, 100, 30], start: .1, end: .9) : null,
        styleRuns: [
          PsdTextStyleRun(
            start: 0,
            length: text.length,
            style: const PsdTextStyle(fontFamily: 'Example-Regular', fontSize: 24),
          ),
        ],
        paragraphs: [
          PsdTextParagraph(
            start: 0,
            length: text.length,
            justification: PsdTextJustification.left,
            list: i == 1 ? const PsdTextList(style: PsdTextListStyle.numeric) : null,
          ),
        ],
      );
      tools.add(PsdTypeTool.fromText(content: content, textIndex: builder.add(content)));
    }
    final PsdGlobalTextEngineData engine = builder.build()!;
    expect(engine.contentFor(tools[2]).path!.start, .1);
    expect(engine.contentFor(tools[0]).path, isNull);
    expect(engine.contentFor(tools[1]).paragraphs.single.list!.style, PsdTextListStyle.numeric);
    expect(engine.contentFor(tools[1]).text, 'One😀\rTwo');
    final Map<String, Object?> root = engine.structure! as Map<String, Object?>;
    final List<Object?> objects = (root['1']! as Map)['1']! as List<Object?>;
    for (int index = 0; index < objects.length; index++) {
      final Map<Object?, Object?> view = (objects[index]! as Map)['1']! as Map;
      expect(view['2'], isEmpty, reason: 'Photoshop 2025 requires an explicitly empty layout cache');
      expect(((view['0']! as List).single as Map)['0'], index);
    }
    expect(() => engine.data[0] = 0, throwsUnsupportedError);
  });

  test('uses Adobe variable-instance names with signed 16.16 coordinates', () {
    final PsdVariableFontInstance source = PsdVariableFontInstance.tryParse('SFPro_110.000wdth_673.000wght')!;
    expect(source.prefix, 'SFPro');
    expect(source.axes, {'wdth': 110, 'wght': 673});
    final PsdVariableFontInstance custom = PsdVariableFontInstance(prefix: 'Example', axes: {'wght': 537.125, 'slnt': -2.9, 'opsz': 14});
    final PsdVariableFontInstance restored = PsdVariableFontInstance.tryParse(custom.postScriptName)!;
    for (final String tag in custom.axes.keys) {
      expect((restored.axes[tag]! * 65536).round(), (custom.axes[tag]! * 65536).round());
    }
    for (final String name in ['Example-Bold', 'Example_1wght_2wght', 'Example_40000wght', 'Example_NaNwght', 'Example_1a!bc']) {
      expect(PsdVariableFontInstance.tryParse(name), isNull);
    }
  });

  test('rejects discontinuous, nonfinite and out-of-range path metadata', () {
    expect(() => PsdTextPath(controlPoints: [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7]), throwsArgumentError);
    expect(() => PsdTextPath(controlPoints: [0, 0, 1, 1, 2, 2, 3, double.nan]), throwsArgumentError);
    expect(() => PsdTextPath(controlPoints: [0, 0, 1, 1, 2, 2, 3, 3], start: .8, end: .2), throwsArgumentError);
  });

  test('does not author global text with unsupported layout settings', () {
    const PsdTextContent plain = PsdTextContent(text: 'A', orientation: PsdTextOrientation.horizontal);
    final PsdGlobalTextBuilder builder = PsdGlobalTextBuilder();
    for (final PsdTextContent unsupported in [
      plain.copyWith(gridInfo: const PsdTextGridInfo(isOn: true)),
      plain.copyWith(pointBase: const PsdTextPoint(x: 4, y: 0)),
      plain.copyWith(smallCapSize: .8),
      plain.copyWith(
        paragraphs: const [
          PsdTextParagraph(
            start: 0,
            length: 1,
            justification: PsdTextJustification.left,
            adjustments: PsdTextParagraphAdjustments(xy: [1, 0]),
          ),
        ],
      ),
    ]) {
      expect(PsdGlobalTextBuilder.supports(unsupported), isFalse);
      expect(() => builder.add(unsupported), throwsArgumentError);
    }
    expect(builder.build(), isNull);
  });
}
