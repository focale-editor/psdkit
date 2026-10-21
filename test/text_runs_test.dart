import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Checks the shared range rules used by character and paragraph styles.
void main() {
  group('text run normalization', () {
    final List<_NormalizationCase> cases = [
      (name: 'default styles', text: 'ABCDE', runs: [], lengths: [6], styles: [0]),
      (name: 'empty text keeps the first supplied style', text: '', runs: [(2, 3, 1), (0, 2, 0)], lengths: [1], styles: [1]),
      (name: 'sparse ranges inherit the preceding style', text: 'ABCDEFGH', runs: [(2, 2, 0), (6, 1, 1)], lengths: [2, 2, 2, 1, 2], styles: [0, 0, 0, 1, 1]),
      (name: 'overlaps start after the preceding range', text: 'ABCDEFGH', runs: [(0, 4, 0), (2, 4, 1)], lengths: [4, 2, 3], styles: [0, 1, 1]),
      (name: 'ranges are clipped to text bounds', text: 'ABCDEFGH', runs: [(-2, 4, 0), (5, 20, 1)], lengths: [2, 3, 4], styles: [0, 0, 1]),
      (name: 'ranges beyond the text supply its style', text: 'ABCDEFGH', runs: [(20, 3, 1)], lengths: [9], styles: [1]),
      (name: 'empty ranges affect the following gap', text: 'ABCDEFGH', runs: [(0, 0, 0), (4, 0, 1)], lengths: [4, 5], styles: [0, 1]),
      (name: 'unsorted ranges are ordered by start', text: 'ABCDEFGH', runs: [(4, 2, 1), (0, 2, 0)], lengths: [2, 2, 2, 3], styles: [0, 0, 1, 1]),
      (name: 'emoji ranges use UTF-16 code units', text: 'A😀B', runs: [(1, 2, 1), (3, 1, 0)], lengths: [1, 2, 2], styles: [1, 1, 0]),
    ];

    for (final _NormalizationCase testCase in cases) {
      test(testCase.name, () {
        final PsdTextContent source = PsdTextContent(
          text: testCase.text,
          orientation: .horizontal,
          styleRuns: [
            for (final (int start, int length, int style) in testCase.runs)
              PsdTextStyleRun(
                start: start,
                length: length,
                style: PsdTextStyle(fontSize: style == 0 ? 12 : 24),
              ),
          ],
          paragraphs: [
            for (final (int start, int length, int style) in testCase.runs) PsdTextParagraph(start: start, length: length, justification: style == 0 ? .left : .center),
          ],
        );

        final Uint8List encoded = PsdTextEngine.encode(source);
        final PsdTextContent decoded = PsdTextEngine.decode(encoded, fallbackText: '', orientation: .horizontal);

        expect(_storedRunLengths(encoded, 'StyleRun'), testCase.lengths);
        expect(_storedRunLengths(encoded, 'ParagraphRun'), testCase.lengths);
        expect(decoded.text, testCase.text);
        if (testCase.text.isEmpty) {
          expect(decoded.styleRuns, isEmpty);
          expect(decoded.paragraphs, isEmpty);
          final Map<String, Object?> styleRun = (_storedRuns(encoded, 'StyleRun')['RunArray']! as List<Object?>).single! as Map<String, Object?>;
          final Map<String, Object?> styleSheet = styleRun['StyleSheet']! as Map<String, Object?>;
          final Map<String, Object?> style = styleSheet['StyleSheetData']! as Map<String, Object?>;
          final Map<String, Object?> paragraphRun = (_storedRuns(encoded, 'ParagraphRun')['RunArray']! as List<Object?>).single! as Map<String, Object?>;
          final Map<String, Object?> paragraphSheet = paragraphRun['ParagraphSheet']! as Map<String, Object?>;
          final Map<String, Object?> paragraph = paragraphSheet['Properties']! as Map<String, Object?>;
          expect(style['FontSize'], 24);
          expect(paragraph['Justification'], 2);
        } else {
          final List<int> logicalLengths = [...testCase.lengths];
          logicalLengths[logicalLengths.length - 1]--;
          expect(decoded.styleRuns.map((run) => run.length), logicalLengths);
          expect(decoded.paragraphs.map((run) => run.length), logicalLengths);
          expect(decoded.styleRuns.map((run) => run.style.fontSize), testCase.styles.map((style) => style == 0 ? 12 : 24));
          expect(decoded.paragraphs.map((run) => run.justification), testCase.styles.map((style) => style == 0 ? PsdTextJustification.left : PsdTextJustification.center));
        }
      });
    }
  });

  group('text run decoding', () {
    final List<_DecodingCase> cases = [
      (lengths: '2 50 1', valueCount: 3, expected: [2, 3]),
      (lengths: '2 3', valueCount: 1, expected: [2]),
      (lengths: '2', valueCount: 3, expected: [2]),
      (lengths: '0 5', valueCount: 2, expected: []),
      (lengths: '-1 5', valueCount: 2, expected: []),
      (lengths: '2 /Invalid 3', valueCount: 3, expected: [2]),
      (lengths: '', valueCount: 2, expected: []),
      (lengths: '5', valueCount: 0, expected: []),
    ];

    for (final _DecodingCase testCase in cases) {
      test('bounds [${testCase.lengths}] with ${testCase.valueCount} values', () {
        final String values = '<< >> ' * testCase.valueCount;
        final Uint8List engine = Uint8List.fromList(
          ('<< /EngineDict << /Editor << /Text (ABCDE\r) >> '
                  '/StyleRun << /RunLengthArray [ ${testCase.lengths} ] /RunArray [ $values ] >> '
                  '/ParagraphRun << /RunLengthArray [ ${testCase.lengths} ] /RunArray [ $values ] >> >> >>')
              .codeUnits,
        );

        final PsdTextContent content = PsdTextEngine.decode(engine, fallbackText: '', orientation: .horizontal);

        expect(content.text, 'ABCDE');
        expect(content.styleRuns.map((run) => run.length), testCase.expected);
        expect(content.paragraphs.map((run) => run.length), testCase.expected);
        int start = 0;
        for (int index = 0; index < testCase.expected.length; index++) {
          expect(content.styleRuns[index].start, start);
          expect(content.paragraphs[index].start, start);
          start += testCase.expected[index];
        }
      });
    }
  });
}

/// Reads stored lengths, including Photoshop's required final paragraph mark.
List<Object?> _storedRunLengths(Uint8List bytes, String section) => _storedRuns(bytes, section)['RunLengthArray']! as List<Object?>;

/// Reads one run section through the public EngineData structure decoder.
Map<String, Object?> _storedRuns(Uint8List bytes, String section) {
  final Map<String, Object?> root = PsdTextEngine.decodeStructure(bytes)! as Map<String, Object?>;
  final Map<String, Object?> engine = root['EngineDict']! as Map<String, Object?>;
  return engine[section]! as Map<String, Object?>;
}

/// Input ranges and expected normalized styles.
typedef _NormalizationCase = ({String name, String text, List<(int, int, int)> runs, List<int> lengths, List<int> styles});

/// Stored arrays and their expected bounded lengths.
typedef _DecodingCase = ({String lengths, int valueCount, List<int> expected});
