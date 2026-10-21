part of '../text.dart';

/// EngineData names corresponding to supported OpenType switches.
const Map<String, String> _engineOpenTypeKeys = {
  'ContextualLigatures': 'calt',
  'Swash': 'swsh',
  'OldStyle': 'onum',
  'StylisticAlternates': 'salt',
  'Titling': 'titl',
  'Ornaments': 'ornm',
  'Ordinals': 'ordn',
  'Fractions': 'frac',
};

/// Numeric Txt2 keys established by Photoshop fixtures in the Photocraft corpus.
const Map<String, String> _globalOpenTypeKeys = {
  '20': 'calt',
  '23': 'frac',
  '24': 'ordn',
  '25': 'swsh',
  '26': 'titl',
  '28': 'salt',
  '29': 'ornm',
};

/// Parses either Photoshop's bare dictionary or an explicitly wrapped dictionary.
_PsdEngineDictionary _parseGlobalEngine(Uint8List data) {
  final _PsdEngineParser probe = _PsdEngineParser(bytes: data).._skipTrivia();
  final Uint8List wrapped = probe._startsWith('<<')
      ? data
      : (BytesBuilder(copy: false)
              ..add([60, 60, 32])
              ..add(data)
              ..add([32, 62, 62]))
            .takeBytes();
  final _PsdEngineParser parser = _PsdEngineParser(bytes: wrapped);
  final Object? root = parser.parse();
  if (root is! _PsdEngineDictionary || parser.offset != wrapped.length) {
    throw const FormatException('Expected a complete Txt2 dictionary');
  }
  return root;
}

/// Follows numeric dictionary keys without coercing unexpected node types.
Object? _globalPath(Object? value, List<String> keys) {
  Object? current = value;
  for (final String key in keys) {
    current = current is _PsdEngineDictionary ? current[key] : null;
  }
  return current;
}

/// Applies only current object data, splitting ranges at both engines' boundaries.
PsdTextContent _applyGlobalText(PsdGlobalTextEngineData global, PsdTypeTool tool) {
  final PsdTextContent content = tool.content;
  final _PsdEngineDictionary root;
  try {
    root = _parseGlobalEngine(global.data);
  } on FormatException {
    return content;
  }
  final List<Object?>? objects = _list(_globalPath(root, ['1', '1']));
  final int index = tool.textIndex;
  if (objects == null || index < 0 || index >= objects.length) {
    return content;
  }
  final Object? model = _globalPath(objects[index], ['0']);
  final String? text = _decodeEngineString(_globalPath(model, ['0']));
  if (text == null || _withoutEngineTerminator(text) != content.text) {
    return content;
  }
  final List<Object?>? globalRuns = _list(_globalPath(model, ['6', '0']));
  if (globalRuns == null) {
    return content;
  }
  final List<PsdTextStyleRun> result = [];
  int offset = 0;
  for (final Object? run in globalRuns) {
    final int? length = _integer(_globalPath(run, ['1']));
    if (length == null || length < 0) {
      return content;
    }
    final int end = (offset + length).clamp(offset, content.text.length);
    final _PsdEngineDictionary? style = _dictionary(_globalPath(run, ['0', '0', '6']));
    while (offset < end) {
      int pieceEnd = end;
      for (final PsdTextStyleRun local in content.styleRuns) {
        for (final int boundary in [local.start, local.start + local.length]) {
          if (boundary > offset && boundary < pieceEnd) {
            pieceEnd = boundary;
          }
        }
      }
      final PsdTextStyle base = content.styleAt(offset) ?? const PsdTextStyle();
      final Map<String, int> features = {...base.openTypeFeatures};
      for (final MapEntry<String, String> feature in _globalOpenTypeKeys.entries) {
        if (_engineBoolean(style?[feature.key]) case final bool enabled) {
          features.putIfAbsent(feature.value, () => enabled ? 1 : 0);
        }
      }
      final int? sets = _integer(style?['85']);
      if (sets != null && sets >= 0 && sets < 1 << 20) {
        for (int bit = 0; bit < 20; bit++) {
          features.putIfAbsent('ss${(bit + 1).toString().padLeft(2, '0')}', () => (sets >> bit) & 1);
        }
      }
      final PsdTextKerning? mode = switch (_integer(style?['11'])) {
        0 => PsdTextKerning.manual,
        1 => PsdTextKerning.metrics,
        2 => PsdTextKerning.optical,
        _ => null,
      };
      result.add(
        PsdTextStyleRun(
          start: offset,
          length: pieceEnd - offset,
          style: base.copyWith(kerningMode: mode, openTypeFeatures: Map.unmodifiable(features)),
        ),
      );
      offset = pieceEnd;
    }
    if (offset == content.text.length) {
      break;
    }
  }
  if (offset != content.text.length) {
    return content;
  }
  return content.copyWith(styleRuns: List.unmodifiable(result));
}

/// Updates existing Photoshop structures without inventing incomplete text objects.
PsdGlobalTextEngineData _updateGlobalText(PsdGlobalTextEngineData global, int index, PsdTextContent content) {
  final _PsdEngineDictionary root = _parseGlobalEngine(global.data);
  final List<Object?>? objects = _list(_globalPath(root, ['1', '1']));
  if (index < 0 || index > 65535 || objects == null || index >= objects.length) {
    throw ArgumentError.value(index, 'textIndex', 'No existing Photoshop text object');
  }
  final _PsdEngineDictionary? object = _dictionary(objects[index]);
  final _PsdEngineDictionary? model = _dictionary(object?['0']);
  final _PsdEngineDictionary? styleContainer = _dictionary(model?['6']);
  final List<Object?>? sourceRuns = _list(styleContainer?['0']);
  if (object == null || model == null || sourceRuns == null || sourceRuns.isEmpty || sourceRuns.any((run) => _dictionary(_globalPath(run, ['0', '0', '6'])) == null)) {
    throw const FormatException('Txt2 object lacks complete Photoshop style runs');
  }
  final String plain = content.text.replaceAll('\r\n', '\r').replaceAll('\n', '\r');
  if (plain.length != content.text.length) {
    throw ArgumentError('Normalize CRLF text before assigning UTF-16 style ranges');
  }
  final String text = '$plain\r';
  final bool changed = _decodeEngineString(model['0']) != text;
  if (changed) {
    object.values.remove('21'); // Cached glyph positions describe the previous text.
    for (final MapEntry<String, Object?> entry in model.values.entries) {
      final _PsdEngineDictionary? container = _dictionary(entry.value);
      final List<Object?>? runs = _list(container?['0']);
      if (entry.key == '6' || runs == null || runs.isEmpty || runs.any((run) => _integer(_globalPath(run, ['1'])) == null)) {
        continue;
      }
      container!.values['0'] = _fitGlobalRuns(runs, text, paragraphs: entry.key == '5');
    }
    final _PsdEngineDictionary? viewRuns = _dictionary(_globalPath(object, ['1', '1']));
    final List<Object?>? runs = _list(viewRuns?['0']);
    if (runs != null && runs.isNotEmpty) {
      viewRuns!.values['0'] = _fitGlobalRuns(runs, text, paragraphs: true);
    }
  }
  model.values['0'] = _globalString(text);
  final List<Object?>? fonts = _list(_globalPath(root, ['0', '1', '0']));
  final List<Object?> updated = [];
  int sourceIndex = 0;
  int sourceEnd = _integer(_globalPath(sourceRuns.first, ['1'])) ?? 0;
  int start = 0;
  for (final _PsdTextRun<PsdTextStyle> run in _normalizeStyles(content.styleRuns, plain.length)) {
    int remaining = run.length;
    while (remaining > 0) {
      while (start >= sourceEnd && sourceIndex + 1 < sourceRuns.length) {
        sourceIndex++;
        sourceEnd += _integer(_globalPath(sourceRuns[sourceIndex], ['1'])) ?? 0;
      }
      final int take = sourceEnd > start ? remaining.clamp(1, sourceEnd - start) : remaining;
      final _PsdEngineDictionary copy = _cloneEngine(sourceRuns[sourceIndex]) as _PsdEngineDictionary;
      copy.values['1'] = take;
      final _PsdEngineDictionary style = _globalPath(copy, ['0', '0', '6'])! as _PsdEngineDictionary;
      _updateGlobalStyle(style, run.value, fonts);
      updated.add(copy);
      start += take;
      remaining -= take;
    }
  }
  styleContainer!.values['0'] = updated;
  final _PsdEngineWriter writer = _PsdEngineWriter();
  _writeEngineValue(writer, root, bare: true);
  return PsdGlobalTextEngineData(data: writer.takeBytes());
}

/// Refits imported run metadata to the new text's UTF-16 length.
List<Object?> _fitGlobalRuns(List<Object?> runs, String text, {required bool paragraphs}) {
  final List<int> lengths = [];
  if (paragraphs) {
    int start = 0;
    for (int i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 13) {
        lengths.add(i + 1 - start);
        start = i + 1;
      }
    }
  } else {
    int left = text.length;
    for (final Object? run in runs) {
      final int length = _integer(_globalPath(run, ['1'])) ?? -1;
      if (length < 0) {
        throw const FormatException('Invalid Txt2 run length');
      }
      if (left == 0) {
        break;
      }
      final int take = length.clamp(0, left);
      lengths.add(take);
      left -= take;
    }
    if (lengths.isEmpty) {
      lengths.add(0);
    }
    lengths[lengths.length - 1] += left;
  }
  return [for (int i = 0; i < lengths.length; i++) (_cloneEngine(runs[i.clamp(0, runs.length - 1)]) as _PsdEngineDictionary)..values['1'] = lengths[i]];
}

/// Writes common character properties over the object's original style dictionary.
void _updateGlobalStyle(_PsdEngineDictionary target, PsdTextStyle style, List<Object?>? fonts) {
  final Map<String, Object?> values = target.values;
  final String? name = style.resolvedFontFamily;
  if (name != null && fonts == null) {
    throw const FormatException('Txt2 has no font list');
  }
  if (name != null && fonts != null) {
    int index = fonts.indexWhere((font) => _decodeEngineString(_globalPath(font, ['0', '0', '0'])) == name);
    if (index < 0) {
      if (fonts.isEmpty) {
        throw const FormatException('Txt2 has no font template');
      }
      final Object? entry = _cloneEngine(fonts.first);
      final _PsdEngineDictionary? font = _dictionary(_globalPath(entry, ['0', '0']));
      if (font == null) {
        throw const FormatException('Invalid Txt2 font template');
      }
      final Object? type = font['2'];
      font.values
        ..clear()
        ..addAll({'0': _globalString(name), '2': ?type});
      index = fonts.length;
      fonts.add(entry);
    }
    values['0'] = index;
  }
  values.addAll({
    if (style.fontSize != null) '1': style.fontSize,
    '2': style.fauxBold,
    '3': style.fauxItalic,
    '4': style.automaticLeading,
    '5': style.lineHeight ?? 0,
    '6': style.horizontalScale,
    '7': style.verticalScale,
    '8': style.tracking ?? 0,
    '11': style.resolvedKerningMode.index,
    '9': style.baselineShift,
    '12': style.fontCaps,
    '13': style.fontBaseline,
    '15': style.strikethrough ? 1 : 0,
    '16': style.underline ? 2 : 0,
    '18': style.ligatures,
    '19': style.discretionaryLigatures,
  });
  for (final MapEntry<String, String> feature in _globalOpenTypeKeys.entries) {
    if (style.openTypeFeatures[feature.value] case final int value) {
      values[feature.key] = value > 0;
    }
  }
  if (style.openTypeFeatures.keys.any((key) => key.startsWith('ss'))) {
    int mask = 0;
    for (int bit = 0; bit < 20; bit++) {
      if ((style.openTypeFeatures['ss${(bit + 1).toString().padLeft(2, '0')}'] ?? 0) > 0) {
        mask |= 1 << bit;
      }
    }
    values['85'] = mask;
  }
  final PsdTextColor? color = style.color;
  final _PsdEngineDictionary? paint = _dictionary(_globalPath(target, ['53', '0']));
  if (color != null && paint == null) {
    throw const FormatException('Txt2 style lacks a fill-color template');
  }
  if (color != null && paint != null) {
    final _PsdEngineWriter encoded = _PsdEngineWriter();
    _writeColor(encoded, color);
    final _PsdEngineDictionary parsed = _PsdEngineParser(bytes: encoded.takeBytes()).parse()! as _PsdEngineDictionary;
    paint.values.addAll({'0': parsed['Type'], '1': parsed['Values']});
  }
}

/// Creates a binary UTF-16 string using the same escaping as EngineData.
_PsdEngineString _globalString(String text) {
  final _PsdEngineWriter writer = _PsdEngineWriter()..unicodeString(text);
  return _PsdEngineParser(bytes: writer.takeBytes()).parse()! as _PsdEngineString;
}

/// Copies mutable containers, retaining immutable scalar and binary-string nodes.
Object? _cloneEngine(Object? value) => switch (value) {
  _PsdEngineDictionary(:final values) => _PsdEngineDictionary(values: {for (final MapEntry<String, Object?> entry in values.entries) entry.key: _cloneEngine(entry.value)}),
  final List<Object?> values => [for (final Object? item in values) _cloneEngine(item)],
  _ => value,
};

/// Serializes parsed engine values while retaining unknown binary strings exactly.
void _writeEngineValue(_PsdEngineWriter writer, Object? value, {bool bare = false}) {
  switch (value) {
    case _PsdEngineDictionary(:final values):
      if (!bare) {
        writer.ascii('<< ');
      }
      for (final MapEntry<String, Object?> entry in values.entries) {
        writer.ascii('/${entry.key} ');
        _writeEngineValue(writer, entry.value);
      }
      if (!bare) {
        writer.ascii('>> ');
      }
    case final List<Object?> values:
      writer.ascii('[ ');
      for (final Object? item in values) {
        _writeEngineValue(writer, item);
      }
      writer.ascii('] ');
    case _PsdEngineString(:final bytes):
      writer.ascii('(');
      writer._bytes.add(_escapePostScript(bytes));
      writer.ascii(') ');
    case _PsdEngineName(:final value):
      writer.ascii('/$value ');
    case final num number:
      if (!number.isFinite) {
        throw const FormatException('Non-finite text-engine number');
      }
      writer.ascii('$number ');
    case final bool flag:
      writer.ascii('$flag ');
    case null:
      writer.ascii('null ');
    default:
      throw const FormatException('Unsupported text-engine value');
  }
}

/// Rejects unsupported layout edits instead of leaving Photoshop's global model stale.
void _validateGlobalTextEdit(PsdTextContent previous, PsdTextContent content) {
  final bool layoutChanged =
      previous.orientation != content.orientation ||
      previous.antiAlias != content.antiAlias ||
      previous.gridding != content.gridding ||
      previous.useFractionalGlyphWidths != content.useFractionalGlyphWidths ||
      !_sameEngineBytes(_globalGridSettings(previous.gridInfo), _globalGridSettings(content.gridInfo)) ||
      previous.shapeType != content.shapeType ||
      previous.pointBase.x != content.pointBase.x ||
      previous.pointBase.y != content.pointBase.y ||
      previous.boxBounds.left != content.boxBounds.left ||
      previous.boxBounds.top != content.boxBounds.top ||
      previous.boxBounds.right != content.boxBounds.right ||
      previous.boxBounds.bottom != content.boxBounds.bottom;
  if (layoutChanged) {
    throw UnsupportedError('Txt2 frame geometry must be edited through its retained structure');
  }
  final List<PsdTextParagraph> oldParagraphs = previous.paragraphs;
  if (content.paragraphs.isEmpty && oldParagraphs.isNotEmpty) {
    throw UnsupportedError('Clearing Txt2 paragraph formatting requires editing its retained structure');
  }
  for (int i = 0; i < content.paragraphs.length; i++) {
    final PsdTextParagraph paragraph = content.paragraphs[i];
    final PsdTextParagraph old = oldParagraphs.isEmpty ? const PsdTextParagraph(start: 0, length: 0, justification: PsdTextJustification.left) : oldParagraphs[i.clamp(0, oldParagraphs.length - 1)];
    final _PsdEngineWriter first = _PsdEngineWriter();
    final _PsdEngineWriter second = _PsdEngineWriter();
    _writeParagraphProperties(first, old);
    _writeParagraphProperties(second, paragraph);
    if (!_sameEngineBytes(first.takeBytes(), second.takeBytes())) {
      throw UnsupportedError('Changing Txt2 paragraph formatting requires editing its retained structure');
    }
  }
  for (final PsdTextStyleRun run in content.styleRuns) {
    final PsdTextStyle old = previous.styleAt(run.start.clamp(0, (previous.text.length - 1).clamp(0, previous.text.length))) ?? previous.styleRuns.lastOrNull?.style ?? const PsdTextStyle();
    if (!_sameEngineBytes(_globalStyleExtensions(old), _globalStyleExtensions(run.style))) {
      throw UnsupportedError('This character-style extension has no established Txt2 mapping');
    }
  }
}

/// Serializes baseline-grid properties whose global layout mapping is not established.
Uint8List _globalGridSettings(PsdTextGridInfo grid) {
  final _PsdEngineWriter writer = _PsdEngineWriter()..ascii([grid.isOn, grid.show, grid.size, grid.leading, grid.alignLineHeightToGrid].toString());
  _writeColor(writer, grid.color);
  _writeColor(writer, grid.leadingFillColor);
  return writer.takeBytes();
}

/// Serializes the style properties whose global numeric keys are not established.
Uint8List _globalStyleExtensions(PsdTextStyle style) {
  final _PsdEngineWriter writer = _PsdEngineWriter()
    ..ascii(
      [
        style.kerning,
        style.baselineDirection,
        style.tsume,
        style.styleRunAlignment,
        style.language,
        style.noBreak,
        style.fillEnabled,
        style.strokeEnabled,
        style.fillFirst,
        style.underlinePosition,
        style.outlineWidth,
        style.characterDirection,
        style.hindiNumbers,
        style.kashida,
        style.diacriticPosition,
      ].toString(),
    );
  final List<String> unsupportedFeatures = [
    for (final MapEntry<String, int> feature in style.openTypeFeatures.entries)
      if (feature.value != 0 && !_globalOpenTypeKeys.containsValue(feature.key) && !RegExp(r'^ss(0[1-9]|1[0-9]|20)$').hasMatch(feature.key)) '${feature.key}:${feature.value}',
  ]..sort();
  writer.ascii(unsupportedFeatures.toString());
  if (style.strokeColor case final PsdTextColor color) {
    _writeColor(writer, color);
  }
  return writer.takeBytes();
}

/// Compares normalized property bytes without introducing a collection dependency.
bool _sameEngineBytes(Uint8List first, Uint8List second) {
  if (first.length != second.length) {
    return false;
  }
  for (int i = 0; i < first.length; i++) {
    if (first[i] != second[i]) {
      return false;
    }
  }
  return true;
}
