part of '../text.dart';

/// Collects complete native text objects and their independent `Txt2` frames.
///
/// Register every live type layer in a newly authored document and use the
/// returned index in its `TySh`. Existing Photoshop documents should instead
/// use `withTextContent`, which preserves their original global resources.
final class PsdGlobalTextBuilder {
  /// Contents in the exact order used by type-tool text indices.
  final List<PsdTextContent> _contents = [];

  /// Creates an empty document-level text engine.
  PsdGlobalTextBuilder();

  /// Whether the verified global mappings cover every active style property.
  static bool supports(PsdTextContent content) =>
      !content.hasUnsupportedGeometry &&
      content.gridding == PsdTextGridding.none &&
      content.useFractionalGlyphWidths &&
      !content.gridInfo.isOn &&
      !content.gridInfo.alignLineHeightToGrid &&
      content.pointBase.x == 0 &&
      content.pointBase.y == 0 &&
      content.superscriptSize == 0.583 &&
      content.superscriptPosition == 0.333 &&
      content.subscriptSize == 0.583 &&
      content.subscriptPosition == 0.333 &&
      content.smallCapSize == 0.7 &&
      content.styleRuns.every(
        (run) =>
            run.style.fillEnabled &&
            !run.style.strokeEnabled &&
            run.style.characterDirection == 0 &&
            !run.style.hindiNumbers &&
            run.style.kashida == 1 &&
            run.style.diacriticPosition == 2 &&
            (!run.style.underline || run.style.underlinePosition == 1) &&
            (run.style.font?.script ?? 0) == 0 &&
            (run.style.font?.synthetic ?? 0) == 0 &&
            run.style.openTypeFeatures.entries.every((entry) => entry.value == 0 || _globalOpenTypeKeys.containsValue(entry.key) || RegExp(r'^ss(?:0[1-9]|1[0-9]|20)$').hasMatch(entry.key)) &&
            run.style.kerning == 0,
      ) &&
      content.paragraphs.every(
        (paragraph) =>
            !paragraph.hasUnsupportedList &&
            (paragraph.list == null || paragraph.list!.tier >= 0 && paragraph.list!.tier <= 8) &&
            !paragraph.hanging &&
            _sameGlobalNumbers(paragraph.adjustments.axis, const [1, 0, 1]) &&
            _sameGlobalNumbers(paragraph.adjustments.xy, const [0, 0]),
      );

  /// Registers one complete object, returning its bounded `TextIndex`.
  int add(PsdTextContent content) {
    if (_contents.length >= 65536 || content.text.contains('\r\n') || !supports(content)) {
      throw ArgumentError('Unsupported global text content');
    }
    _contents.add(content);
    return _contents.length - 1;
  }

  /// Serializes fonts, models, paragraph/style runs, views and frames together.
  PsdGlobalTextEngineData? build() {
    if (_contents.isEmpty) {
      return null;
    }
    final _PsdEngineDictionary root = _parseGlobalEngine(base64Decode(_globalTextTemplate));
    final List<Object?> fonts = _list(_globalPath(root, ['0', '1', '0']))!;
    final List<Object?> objects = [];
    final List<Object?> frames = [];
    for (final PsdTextContent content in _contents) {
      final List<Object?> styles = [];
      for (final _PsdTextRun<PsdTextStyle> run in _normalizeStyles(content.styleRuns, content.text.length)) {
        final String name = run.value.resolvedFontFamily ?? 'ArialMT';
        if (!fonts.any((font) => _decodeEngineString(_globalPath(font, ['0', '0', '0'])) == name)) {
          fonts.add(
            _globalDictionary({
              '0': _globalDictionary({
                '99': const _PsdEngineName(value: 'CoolTypeFont'),
                '0': _globalDictionary({'0': _globalString(name), '2': run.value.font?.fontType ?? 0}),
              }),
            }),
          );
        }
        final _PsdEngineDictionary style = _globalDictionary({
          '53': _globalDictionary({'99': const _PsdEngineName(value: 'SimplePaint'), '0': _globalDictionary({})}),
        });
        _updateGlobalStyle(style, run.value, fonts);
        style.values.addAll({'35': run.value.baselineDirection, '36': run.value.tsume, '37': run.value.styleRunAlignment, '38': run.value.language, '52': run.value.noBreak});
        styles.add(
          _globalDictionary({
            '0': _globalDictionary({
              '0': _globalDictionary({'0': _globalString(''), '5': 0, '6': style}),
            }),
            '1': run.length,
          }),
        );
      }
      final List<Object?> paragraphs = [
        for (final _PsdTextRun<PsdTextParagraph> run in _normalizeParagraphs(content.paragraphs, content.text.length))
          _globalDictionary({
            '0': _globalDictionary({
              '0': _globalDictionary({'0': _globalString(''), '5': _globalParagraph(run.value), '6': 0}),
            }),
            '1': run.length,
          }),
      ];
      objects.add(
        _globalDictionary({
          '0': _globalDictionary({
            '0': _globalString('${content.text.replaceAll('\n', '\r')}\r'),
            '5': _globalDictionary({'0': paragraphs}),
            '6': _globalDictionary({'0': styles}),
            '10': _globalDictionary({'0': content.orientation == PsdTextOrientation.vertical && content.styleRuns.any((run) => run.style.baselineDirection == 2) ? 4 : 1, '2': true}),
          }),
          '1': _globalDictionary({
            '0': [
              _globalDictionary({'0': frames.length}),
            ],
            '2': <Object?>[],
          }),
        }),
      );
      frames.add(_globalFrame(content));
    }
    final _PsdEngineWriter writer = _PsdEngineWriter();
    (_globalPath(root, ['0', '8'])! as _PsdEngineDictionary).values['0'] = frames;
    (_globalPath(root, ['1'])! as _PsdEngineDictionary).values['1'] = objects;
    _writeEngineValue(writer, root, bare: true);
    return PsdGlobalTextEngineData(data: writer.takeBytes());
  }
}

/// Compares bounded engine settings without approximating active adjustments.
bool _sameGlobalNumbers(List<double> values, List<double> expected) => values.length == expected.length && values.indexed.every((entry) => entry.$2 == expected[entry.$1]);

/// Creates a mutable internal dictionary for verified native text structures.
_PsdEngineDictionary _globalDictionary(Map<String, Object?> values) => _PsdEngineDictionary(values: values);

/// Encodes paragraph properties shared by the local and global Adobe engines.
_PsdEngineDictionary _globalParagraph(PsdTextParagraph paragraph) => _globalDictionary({
  '0': _encodeJustification(paragraph.justification),
  '1': paragraph.firstLineIndent,
  '2': paragraph.startIndent,
  '3': paragraph.endIndent,
  '4': paragraph.spaceBefore,
  '5': paragraph.spaceAfter,
  '7': paragraph.automaticLeading,
  '9': paragraph.automaticHyphenation,
  '10': paragraph.hyphenatedWordSize,
  '11': paragraph.preHyphen,
  '12': paragraph.postHyphen,
  '13': paragraph.consecutiveHyphens,
  '14': paragraph.zone,
  '15': true,
  '8': paragraph.leadingType,
  '21': paragraph.burasagari,
  '24': paragraph.kinsokuOrder,
  '29': paragraph.everyLineComposer,
  '36': paragraph.list?.style.index,
  '37': paragraph.list?.tier ?? 0,
  '17': [paragraph.wordSpacing.minimum, paragraph.wordSpacing.desired, paragraph.wordSpacing.maximum],
  '18': [paragraph.letterSpacing.minimum, paragraph.letterSpacing.desired, paragraph.letterSpacing.maximum],
  '19': [paragraph.glyphSpacing.minimum, paragraph.glyphSpacing.desired, paragraph.glyphSpacing.maximum],
});

/// Encodes one independent frame in the coordinate system of its text tool.
_PsdEngineDictionary _globalFrame(PsdTextContent content) {
  final PsdTextPath? path = content.path;
  if (path != null) {
    return _globalDictionary({
      '0': _globalDictionary({
        '1': _globalDictionary({'0': path.controlPoints}),
        '2': _globalDictionary({
          '0': 2,
          '2': [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
          '6': [path.start ?? -1.0, path.end ?? -1.0],
          '11': _globalDictionary({'0': path.reversed, '3': 0, '5': 0, '7': false}),
        }),
      }),
    });
  }
  if (content.shapeType == PsdTextShapeType.box) {
    final PsdTextBox box = content.boxBounds;
    final List<(double, double)> corners = [(box.left, box.top), (box.right, box.top), (box.right, box.bottom), (box.left, box.bottom), (box.left, box.top)];
    return _globalDictionary({
      '0': _globalDictionary({
        '1': _globalDictionary({
          '0': [
            for (int i = 0; i < 4; i++) ...[corners[i].$1, corners[i].$2, corners[i].$1, corners[i].$2, corners[i + 1].$1, corners[i + 1].$2, corners[i + 1].$1, corners[i + 1].$2],
          ],
        }),
        '2': _globalDictionary({
          '0': 1,
          if (content.orientation == PsdTextOrientation.vertical) '1': 2,
          '6': [-2.0, -2.0],
          '11': _globalDictionary({'4': -2, '18': -2.0}),
        }),
      }),
    });
  }
  return _globalDictionary({
    '0': _globalDictionary({
      '2': _globalDictionary({
        if (content.orientation == PsdTextOrientation.vertical) '1': 2,
        '6': [-1.0, -1.0],
        '11': _globalDictionary({'4': -1, '7': false}),
      }),
    }),
  });
}
