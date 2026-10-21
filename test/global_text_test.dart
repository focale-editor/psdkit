@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Exercises global text semantics against independently authored Photoshop data.
void main() {
  for (final (String name, PsdTextKerning mode) in [('kerning-metrics', PsdTextKerning.metrics), ('kerning-optical', PsdTextKerning.optical), ('kerning-off', PsdTextKerning.manual)]) {
    test('Resolves $name from the global engine', () {
      final PsdDocument document = _fixture(name);
      final PsdLayer layer = document.layers.firstWhere((layer) => layer.typeTool != null);
      expect(document.globalTextEngineData!.structure, isA<Map<String, Object?>>());
      expect(document.textContentFor(layer)!.styleRuns.map((run) => run.style.resolvedKerningMode).toSet(), {mode});
    });
  }

  test('Resolves OpenType flags omitted from TySh EngineData', () {
    final PsdDocument document = _fixture('opentype-fractions');
    final PsdLayer layer = document.layers.firstWhere((layer) => layer.typeTool != null);
    expect(document.textContentFor(layer)!.styleRuns.first.style.openTypeFeatures['frac'], 1);
  });

  test('Keeps opaque object metadata and fits Unicode text, styles and paragraphs', () {
    final PsdDocument document = _fixture('kerning-optical');
    final int layerIndex = document.layers.indexWhere((layer) => layer.typeTool != null);
    final PsdTextContent original = document.textContentFor(document.layers[layerIndex])!;
    const String text = 'A😀\rSecond line';
    final PsdTextContent edited = original.copyWith(
      text: text,
      styleRuns: [
        PsdTextStyleRun(start: 0, length: 3, style: original.styleRuns.first.style.copyWith(kerningMode: PsdTextKerning.manual)),
        PsdTextStyleRun(
          start: 3,
          length: text.length - 3,
          style: original.styleRuns.first.style.copyWith(fontFamily: 'ReplacementFont-Regular', kerningMode: PsdTextKerning.optical, openTypeFeatures: {'frac': 1, 'ss03': 1}),
        ),
      ],
    );
    final PsdDocument result = PsdCodec.decode(PsdCodec.encode(document.withTextContent(layerIndex, edited)));
    final PsdLayer layer = result.layers[layerIndex];
    final PsdTextContent content = result.textContentFor(layer)!;
    expect(content.text, text);
    expect(content.styleAt(1)!.resolvedKerningMode, PsdTextKerning.manual);
    expect(content.styleAt(4)!.resolvedKerningMode, PsdTextKerning.optical);
    expect(content.styleAt(4)!.resolvedFontFamily, 'ReplacementFont-Regular');
    expect(content.styleAt(4)!.copyWith(automaticKerning: false).resolvedKerningMode, PsdTextKerning.manual);
    expect(content.styleAt(4)!.openTypeFeatures['ss03'], 1);
    expect(content.styleAt(4)!.openTypeFeatures['frac'], 1);
    expect(layer.typeTool!.textIndex, document.layers[layerIndex].typeTool!.textIndex);
    final Map<String, Object?> before = document.globalTextEngineData!.structure! as Map<String, Object?>;
    final Map<String, Object?> after = result.globalTextEngineData!.structure! as Map<String, Object?>;
    expect(_at(after, ['98']), _at(before, ['98']));
    final List<Object?> fonts = _at(after, ['0', '1', '0']) as List<Object?>;
    expect(fonts.map((font) => _at(font as Map<String, Object?>, ['0', '0', '0'])), contains('ReplacementFont-Regular'));
    final Map<String, Object?> object = ((_at(after, ['1', '1']) as List<Object?>).first as Map<String, Object?>);
    final List<Object?> paragraphs = _at(object, ['0', '5', '0']) as List<Object?>;
    expect(paragraphs.map((run) => (run as Map<String, Object?>)['1']), [4, 12]);
    expect(object.containsKey('21'), isFalse);
    expect(layer.channels.map((channel) => channel.data), document.layers[layerIndex].channels.map((channel) => channel.data));
  });

  test('Rejects layout changes without an established global-engine mapping', () {
    final PsdDocument document = _fixture('kerning-optical');
    final int index = document.layers.indexWhere((layer) => layer.typeTool != null);
    final PsdTextContent content = document.textContentFor(document.layers[index])!;
    expect(() => document.withTextContent(index, content.copyWith(gridInfo: const PsdTextGridInfo(isOn: true))), throwsUnsupportedError);
    expect(
      () => document.withTextContent(
        index,
        content.copyWith(
          styleRuns: [
            PsdTextStyleRun(start: 0, length: content.text.length, style: content.styleRuns.first.style.copyWith(kerning: 50)),
          ],
        ),
      ),
      throwsUnsupportedError,
    );
    expect(() => document.withTextContent(index, content.copyWith(pointBase: const PsdTextPoint(x: 12, y: 34))), throwsUnsupportedError);
    expect(
      () => document.withTextContent(
        index,
        content.copyWith(
          paragraphs: [PsdTextParagraph(start: 0, length: content.text.length, justification: PsdTextJustification.right)],
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test('Ignores stale global text and rejects missing object slots', () {
    final PsdDocument document = _fixture('kerning-optical');
    final PsdTypeTool tool = document.layers.firstWhere((layer) => layer.typeTool != null).typeTool!;
    expect(document.globalTextEngineData!.contentFor(tool.withText('Different')).styleRuns.every((run) => run.style.kerningMode == null), isTrue);
    expect(() => document.globalTextEngineData!.withContent(0x7fffffff, tool.content), throwsArgumentError);
    expect(PsdGlobalTextEngineData(data: Uint8List.fromList('/0 ['.codeUnits)).tryStructure, isNull);
  });
}

/// Reads one pinned Photoshop oracle.
PsdDocument _fixture(String name) => PsdCodec.decode(File('test/corpus/photocraft/photoshop/text/$name.psd').readAsBytesSync());

/// Looks up a public engine dictionary path for structural assertions.
Object? _at(Map<String, Object?> root, List<String> keys) {
  Object? value = root;
  for (final String key in keys) {
    value = (value as Map<String, Object?>)[key];
  }
  return value;
}
