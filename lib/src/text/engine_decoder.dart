part of '../text.dart';

/// Extracts semantic text information from opaque Adobe [engineData].
PsdTextContent _decodeTextEngine(
  Uint8List? engineData, {
  required String fallbackText,
  required PsdTextOrientation orientation,
  PsdTextAntiAlias fallbackAntiAlias = PsdTextAntiAlias.sharp,
  PsdTextAntiAlias? antiAliasOverride,
  PsdTextGridding gridding = PsdTextGridding.none,
}) {
  if (engineData == null) {
    return PsdTextContent(
      text: fallbackText,
      orientation: orientation,
      antiAlias: fallbackAntiAlias,
      gridding: gridding,
      hasShapeMetadata: false,
    );
  }
  try {
    final Object? rootValue = _PsdEngineParser(bytes: engineData).parse();
    final _PsdEngineDictionary? root = _dictionary(rootValue);
    final _PsdEngineDictionary? engine = _dictionary(root?['EngineDict']);
    final _PsdEngineDictionary? resources = _dictionary(root?['ResourceDict']);
    final _PsdEngineDictionary? editor = _dictionary(engine?['Editor']);
    final String text = _decodeEngineString(editor?['Text']) ?? fallbackText;
    final String logicalText = _withoutEngineTerminator(text);
    final List<PsdTextFont> fonts = _readFonts(resources);
    final _PsdTextShapeData shape = _readShape(engine);
    return PsdTextContent(
      text: logicalText,
      orientation: orientation,
      styleRuns: _readStyleRuns(engine, resources, fonts, logicalText.length),
      paragraphs: _readParagraphs(engine, resources, logicalText.length),
      antiAlias:
          antiAliasOverride ??
          _decodeEngineAntiAlias(
            _integer(engine?['AntiAlias']),
            fallback: fallbackAntiAlias,
          ),
      gridding: gridding,
      useFractionalGlyphWidths: _engineBoolean(engine?['UseFractionalGlyphWidths']) ?? true,
      gridInfo: _readGridInfo(engine),
      shapeType: shape.type,
      hasShapeMetadata: shape.isPresent,
      pointBase: shape.point,
      boxBounds: shape.box,
      superscriptSize: _number(resources?['SuperscriptSize']) ?? 0.583,
      superscriptPosition: _number(resources?['SuperscriptPosition']) ?? 0.333,
      subscriptSize: _number(resources?['SubscriptSize']) ?? 0.583,
      subscriptPosition: _number(resources?['SubscriptPosition']) ?? 0.333,
      smallCapSize: _number(resources?['SmallCapSize']) ?? 0.7,
    );
  } on FormatException {
    return PsdTextContent(
      text: fallbackText,
      orientation: orientation,
      antiAlias: fallbackAntiAlias,
      gridding: gridding,
      hasShapeMetadata: false,
    );
  }
}

/// Reads font metadata from the engine resource dictionary.
List<PsdTextFont> _readFonts(_PsdEngineDictionary? resources) {
  final List<Object?>? fontSet = _list(resources?['FontSet']);
  if (fontSet == null) {
    return const <PsdTextFont>[];
  }
  final List<PsdTextFont> fonts = <PsdTextFont>[];
  for (final Object? entry in fontSet) {
    final _PsdEngineDictionary? font = _dictionary(entry);
    final String? name = _decodeEngineString(font?['Name']);
    if (name == null) {
      continue;
    }
    fonts.add(
      PsdTextFont(
        name: _withoutTerminalNull(name),
        script: _integer(font?['Script']) ?? 0,
        fontType: _integer(font?['FontType']) ?? 0,
        synthetic: _integer(font?['Synthetic']) ?? 0,
      ),
    );
  }
  return fonts;
}

/// Reads style runs and resolves inherited sheets and font references.
List<PsdTextStyleRun> _readStyleRuns(
  _PsdEngineDictionary? engine,
  _PsdEngineDictionary? resources,
  List<PsdTextFont> fonts,
  int textLength,
) {
  final _PsdEngineDictionary? runs = _dictionary(engine?['StyleRun']);
  final int normalIndex = _integer(resources?['TheNormalStyleSheet']) ?? 0;
  final _PsdEngineDictionary? normalData = _resourceStyleData(resources, normalIndex);
  final _PsdEngineDictionary? defaultData = _styleData(_dictionary(runs?['DefaultRunData']));
  final List<PsdTextStyleRun> result = <PsdTextStyleRun>[];
  for (final _PsdTextRange<_PsdEngineDictionary?> range in _readEngineRuns(runs, textLength: textLength)) {
    final _PsdEngineDictionary? run = range.value;
    final _PsdEngineDictionary? sheet = _dictionary(run?['StyleSheet']);
    final int sheetIndex = _integer(sheet?['DefaultStyleSheet']) ?? normalIndex;
    final _PsdEngineDictionary data = _mergeDictionaries(<_PsdEngineDictionary?>[
      normalData,
      defaultData,
      _resourceStyleData(resources, sheetIndex),
      _dictionary(sheet?['StyleSheetData']),
    ]);
    final int? fontIndex = _integer(data['Font']);
    final PsdTextFont? font = fontIndex != null && fontIndex >= 0 && fontIndex < fonts.length ? fonts[fontIndex] : null;
    final bool automaticLeading = _engineBoolean(data['AutoLeading']) ?? _number(data['Leading']) == null;
    result.add(
      PsdTextStyleRun(
        start: range.start,
        length: range.length,
        style: PsdTextStyle(
          fontFamily: font?.name,
          font: font,
          fontSize: _number(data['FontSize']),
          color: _readColor(data['FillColor']),
          tracking: _number(data['Tracking']),
          lineHeight: automaticLeading ? null : _number(data['Leading']),
          automaticLeading: automaticLeading,
          horizontalScale: _number(data['HorizontalScale']) ?? 1,
          verticalScale: _number(data['VerticalScale']) ?? 1,
          automaticKerning: _engineBoolean(data['AutoKerning']) ?? true,
          kerning: _number(data['Kerning']) ?? 0,
          openTypeFeatures: Map.unmodifiable({
            for (final MapEntry<String, String> feature in _engineOpenTypeKeys.entries)
              if (_engineBoolean(data[feature.key]) case final bool enabled) feature.value: enabled ? 1 : 0,
          }),
          baselineShift: _number(data['BaselineShift']) ?? 0,
          fontCaps: _integer(data['FontCaps']) ?? 0,
          fontBaseline: _integer(data['FontBaseline']) ?? 0,
          fauxBold: _engineBoolean(data['FauxBold']) ?? false,
          fauxItalic: _engineBoolean(data['FauxItalic']) ?? false,
          underline: _engineBoolean(data['Underline']) ?? false,
          strikethrough: _engineBoolean(data['Strikethrough']) ?? false,
          ligatures: _engineBoolean(data['Ligatures']) ?? true,
          discretionaryLigatures: _engineBoolean(data['DLigatures']) ?? false,
          baselineDirection: _integer(data['BaselineDirection']) ?? 2,
          tsume: _number(data['Tsume']) ?? 0,
          styleRunAlignment: _integer(data['StyleRunAlignment']) ?? 2,
          language: _integer(data['Language']) ?? 0,
          noBreak: _engineBoolean(data['NoBreak']) ?? false,
          strokeColor: _readColor(data['StrokeColor']),
          fillEnabled: _engineBoolean(data['FillFlag']) ?? true,
          strokeEnabled: _engineBoolean(data['StrokeFlag']) ?? false,
          fillFirst: _engineBoolean(data['FillFirst']) ?? true,
          underlinePosition: _number(data['YUnderline']) ?? 1,
          outlineWidth: _number(data['OutlineWidth']) ?? 1,
          characterDirection: _integer(data['CharacterDirection']) ?? 0,
          hindiNumbers: _engineBoolean(data['HindiNumbers']) ?? false,
          kashida: _integer(data['Kashida']) ?? 1,
          diacriticPosition: _integer(data['DiacriticPos']) ?? 2,
        ),
      ),
    );
  }
  return result;
}

/// Reads paragraph ranges from the text engine.
List<PsdTextParagraph> _readParagraphs(
  _PsdEngineDictionary? engine,
  _PsdEngineDictionary? resources,
  int textLength,
) {
  final _PsdEngineDictionary? runs = _dictionary(engine?['ParagraphRun']);
  final int normalIndex = _integer(resources?['TheNormalParagraphSheet']) ?? 0;
  final _PsdEngineDictionary? normalData = _resourceParagraphData(resources, normalIndex);
  final _PsdEngineDictionary? defaultRun = _dictionary(runs?['DefaultRunData']);
  final _PsdEngineDictionary? defaultSheet = _dictionary(defaultRun?['ParagraphSheet']);
  final _PsdEngineDictionary? defaultData = _dictionary(defaultSheet?['Properties']);
  final _PsdEngineDictionary? defaultAdjustments = _dictionary(defaultRun?['Adjustments']);
  final List<PsdTextParagraph> result = <PsdTextParagraph>[];
  for (final _PsdTextRange<_PsdEngineDictionary?> range in _readEngineRuns(runs, textLength: textLength)) {
    final _PsdEngineDictionary? run = range.value;
    final _PsdEngineDictionary? sheet = _dictionary(run?['ParagraphSheet']);
    final int sheetIndex = _integer(sheet?['DefaultStyleSheet']) ?? normalIndex;
    final _PsdEngineDictionary data = _mergeDictionaries(<_PsdEngineDictionary?>[
      normalData,
      defaultData,
      _resourceParagraphData(resources, sheetIndex),
      _dictionary(sheet?['Properties']),
    ]);
    final _PsdEngineDictionary adjustments = _mergeDictionaries(<_PsdEngineDictionary?>[
      defaultAdjustments,
      _dictionary(run?['Adjustments']),
    ]);
    final int justification = _integer(data['Justification']) ?? 0;
    result.add(
      PsdTextParagraph(
        start: range.start,
        length: range.length,
        justification: _decodeJustification(justification),
        firstLineIndent: _number(data['FirstLineIndent']) ?? 0,
        startIndent: _number(data['StartIndent']) ?? 0,
        endIndent: _number(data['EndIndent']) ?? 0,
        spaceBefore: _number(data['SpaceBefore']) ?? 0,
        spaceAfter: _number(data['SpaceAfter']) ?? 0,
        automaticHyphenation: _engineBoolean(data['AutoHyphenate']) ?? true,
        hyphenatedWordSize: _integer(data['HyphenatedWordSize']) ?? 6,
        preHyphen: _integer(data['PreHyphen']) ?? 2,
        postHyphen: _integer(data['PostHyphen']) ?? 2,
        consecutiveHyphens: _integer(data['ConsecutiveHyphens']) ?? 8,
        zone: _number(data['Zone']) ?? 36,
        wordSpacing: _readSpacing(data['WordSpacing'], fallback: const PsdTextSpacing(minimum: 0.8, desired: 1, maximum: 1.33)),
        letterSpacing: _readSpacing(data['LetterSpacing'], fallback: const PsdTextSpacing(minimum: 0, desired: 0, maximum: 0)),
        glyphSpacing: _readSpacing(data['GlyphSpacing'], fallback: const PsdTextSpacing(minimum: 1, desired: 1, maximum: 1)),
        automaticLeading: _number(data['AutoLeading']) ?? 1.2,
        leadingType: _integer(data['LeadingType']) ?? 0,
        hanging: _engineBoolean(data['Hanging']) ?? false,
        burasagari: _engineBoolean(data['Burasagari']) ?? false,
        kinsokuOrder: _integer(data['KinsokuOrder']) ?? 0,
        everyLineComposer: _engineBoolean(data['EveryLineComposer']) ?? false,
        adjustments: PsdTextParagraphAdjustments(
          axis: _numbers(adjustments['Axis']) ?? const <double>[1, 0, 1],
          xy: _numbers(adjustments['XY']) ?? const <double>[0, 0],
        ),
      ),
    );
  }
  return result;
}

/// Reads an Adobe color dictionary, keeping its normalized values.
PsdTextColor? _readColor(Object? value) {
  final _PsdEngineDictionary? color = _dictionary(value);
  final int? type = _integer(color?['Type']);
  final List<Object?>? components = _list(color?['Values']);
  if (type == null || components == null) {
    return null;
  }

  final PsdTextColorSpace? colorSpace = PsdTextColorSpace.values.where((space) => space.engineType == type && components.length > space.componentCount).firstOrNull;
  if (colorSpace == null) {
    return null;
  }
  return PsdTextColor.fromValues(colorSpace, [
    for (int index = 0; index <= colorSpace.componentCount; index++)
      switch (_number(components[index])) {
        final double value when value.isFinite => value,
        _ => 0,
      },
  ]);
}

/// Reads baseline-grid properties from [engine].
PsdTextGridInfo _readGridInfo(_PsdEngineDictionary? engine) {
  final _PsdEngineDictionary? grid = _dictionary(engine?['GridInfo']);
  return PsdTextGridInfo(
    isOn: _engineBoolean(grid?['GridIsOn']) ?? false,
    show: _engineBoolean(grid?['ShowGrid']) ?? false,
    size: _number(grid?['GridSize']) ?? 18,
    leading: _number(grid?['GridLeading']) ?? 22,
    color: _readColor(grid?['GridColor']) ?? const PsdTextColor(alpha: 0, red: 0, green: 0, blue: 255),
    leadingFillColor: _readColor(grid?['GridLeadingFillColor']) ?? _readColor(grid?['GridColor']) ?? const PsdTextColor(alpha: 0, red: 0, green: 0, blue: 255),
    alignLineHeightToGrid: _engineBoolean(grid?['AlignLineHeightToGridFlags']) ?? false,
  );
}

/// Reads point or box geometry from the rendered text-engine tree.
_PsdTextShapeData _readShape(_PsdEngineDictionary? engine) {
  final _PsdEngineDictionary? rendered = _dictionary(engine?['Rendered']);
  final _PsdEngineDictionary? shapes = _dictionary(rendered?['Shapes']);
  final List<Object?>? children = _list(shapes?['Children']);
  final _PsdEngineDictionary? child = children == null || children.isEmpty ? null : _dictionary(children.first);
  final _PsdEngineDictionary? cookie = _dictionary(child?['Cookie']) ?? _dictionary(child?['Cookies']);
  final _PsdEngineDictionary? photoshop = _dictionary(cookie?['Photoshop']);
  final List<double>? point = _numbers(photoshop?['PointBase']);
  final List<double>? box = _numbers(photoshop?['BoxBounds']);
  final PsdTextShapeType type = _integer(photoshop?['ShapeType']) == 1 ? PsdTextShapeType.box : PsdTextShapeType.point;
  return _PsdTextShapeData(
    isPresent: photoshop != null && (photoshop.values.containsKey('ShapeType') || point != null || box != null),
    type: type,
    point: point != null && point.length >= 2 ? PsdTextPoint(x: point[0], y: point[1]) : PsdTextPoint.zero,
    box: box != null && box.length >= 4 ? PsdTextBox(left: box[0], top: box[1], right: box[2], bottom: box[3]) : PsdTextBox.zero,
  );
}

/// Geometry decoded from the text engine's rendered tree.
final class _PsdTextShapeData {
  /// Whether the rendered tree contained Photoshop shape metadata.
  final bool isPresent;

  /// Point-text or box-text mode.
  final PsdTextShapeType type;

  /// Point-text anchor.
  final PsdTextPoint point;

  /// Box-text flow rectangle.
  final PsdTextBox box;

  /// Creates decoded text geometry.
  const _PsdTextShapeData({
    required this.isPresent,
    required this.type,
    required this.point,
    required this.box,
  });
}

/// Converts Adobe's text-engine paragraph value to a semantic alignment.
PsdTextJustification _decodeJustification(int value) => switch (value) {
  0 => PsdTextJustification.left,
  1 => PsdTextJustification.right,
  2 => PsdTextJustification.center,
  3 => PsdTextJustification.justifyLeft,
  4 => PsdTextJustification.justifyRight,
  5 => PsdTextJustification.justifyCenter,
  6 => PsdTextJustification.justifyAll,
  _ => PsdTextJustification.left,
};

/// Decodes an antialiasing index from Adobe text-engine data.
PsdTextAntiAlias _decodeEngineAntiAlias(
  int? value, {
  required PsdTextAntiAlias fallback,
}) => switch (value) {
  0 => PsdTextAntiAlias.none,
  1 => PsdTextAntiAlias.crisp,
  2 => PsdTextAntiAlias.strong,
  3 => PsdTextAntiAlias.smooth,
  4 => PsdTextAntiAlias.sharp,
  _ => fallback,
};

/// Casts [value] to an engine dictionary when possible.
_PsdEngineDictionary? _dictionary(Object? value) => value is _PsdEngineDictionary ? value : null;

/// Casts [value] to an engine list when possible.
List<Object?>? _list(Object? value) => value is List<Object?> ? value : null;

/// Returns the dictionary at [index] in [value], when present.
_PsdEngineDictionary? _dictionaryAt(Object? value, int index) {
  final List<Object?>? values = _list(value);
  return values != null && index >= 0 && index < values.length ? _dictionary(values[index]) : null;
}

/// Extracts character-style data from a style-run or resource entry.
_PsdEngineDictionary? _styleData(_PsdEngineDictionary? value) {
  final _PsdEngineDictionary? sheet = _dictionary(value?['StyleSheet']);
  return _dictionary(sheet?['StyleSheetData']) ?? _dictionary(value?['StyleSheetData']);
}

/// Returns a resource character-style sheet by [index].
_PsdEngineDictionary? _resourceStyleData(
  _PsdEngineDictionary? resources,
  int index,
) => _dictionary(_dictionaryAt(resources?['StyleSheetSet'], index)?['StyleSheetData']);

/// Returns a resource paragraph-style sheet by [index].
_PsdEngineDictionary? _resourceParagraphData(
  _PsdEngineDictionary? resources,
  int index,
) => _dictionary(_dictionaryAt(resources?['ParagraphSheetSet'], index)?['Properties']);

/// Merges inherited EngineData dictionaries from least to most specific.
_PsdEngineDictionary _mergeDictionaries(List<_PsdEngineDictionary?> dictionaries) {
  final Map<String, Object?> values = <String, Object?>{};
  for (final _PsdEngineDictionary? dictionary in dictionaries) {
    if (dictionary != null) {
      values.addAll(dictionary.values);
    }
  }
  return _PsdEngineDictionary(values: values);
}

/// Converts an engine array into numeric values.
List<double>? _numbers(Object? value) {
  final List<Object?>? values = _list(value);
  if (values == null || values.any((entry) => entry is! num)) {
    return null;
  }
  return <double>[for (final Object? entry in values) (entry! as num).toDouble()];
}

/// Reads a spacing triplet, falling back when the value is absent or malformed.
PsdTextSpacing _readSpacing(
  Object? value, {
  required PsdTextSpacing fallback,
}) {
  final List<double>? values = _numbers(value);
  return values != null && values.length >= 3
      ? PsdTextSpacing(
          minimum: values[0],
          desired: values[1],
          maximum: values[2],
        )
      : fallback;
}

/// Converts an engine numeric value to a double.
double? _number(Object? value) => value is num ? value.toDouble() : null;

/// Converts an engine numeric value to an integer.
int? _integer(Object? value) => value is num ? value.toInt() : null;

/// Converts Boolean and historical zero-or-one engine values to a Boolean.
bool? _engineBoolean(Object? value) => value is bool
    ? value
    : value is num
    ? value != 0
    : null;
