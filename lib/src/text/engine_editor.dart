part of '../text.dart';

/// Replaces the PostScript string assigned to `/Text` in [engineData].
Uint8List _replaceEngineText(Uint8List engineData, String text) {
  final ({int start, int end, Uint8List value})? target = _findTextString(engineData);
  if (target == null) {
    return engineData;
  }
  final int oldLength = _withoutEngineTerminator(_decodeEngineString(_PsdEngineString(bytes: target.value)) ?? '').length;
  final Uint8List encoded = _encodeEngineString(text, target.value);
  final BytesBuilder output = BytesBuilder(copy: false)
    ..add(Uint8List.sublistView(engineData, 0, target.start))
    ..add(_escapePostScript(encoded))
    ..add(Uint8List.sublistView(engineData, target.end));
  Uint8List updated = output.takeBytes();
  updated = _replaceRunLengths(updated, 'StyleRun', oldLength: oldLength, newLength: text.length);
  updated = _replaceRunLengths(updated, 'ParagraphRun', oldLength: oldLength, newLength: text.length);
  return updated;
}

/// Finds and decodes the literal string assigned to the first `/Text` key.
({int start, int end, Uint8List value})? _findTextString(Uint8List source) {
  int index = 0;
  while (index < source.length) {
    if (source[index] == 0x28) {
      index = _skipLiteralString(source, index);
      continue;
    }
    if (source[index] == 0x2f && _matchesName(source, index + 1, 'Text')) {
      index += 5;
      while (index < source.length && _isWhitespace(source[index])) {
        index++;
      }
      if (index < source.length && source[index] == 0x28) {
        final _PsdEngineParser parser = _PsdEngineParser(bytes: source, offset: index);
        final _PsdEngineString value = parser.readLiteralString();
        return (start: index + 1, end: parser.offset - 1, value: value.bytes);
      }
    }
    index++;
  }
  return null;
}

/// Adjusts one engine run-length array after the text length changes.
Uint8List _replaceRunLengths(Uint8List source, String section, {required int oldLength, required int newLength}) {
  if (oldLength == newLength) {
    return source;
  }
  final int sectionOffset = _findName(source, section);
  if (sectionOffset < 0) {
    return source;
  }
  final int lengthsOffset = _findName(source, 'RunLengthArray', start: sectionOffset + section.length + 1);
  if (lengthsOffset < 0) {
    return source;
  }
  int opening = lengthsOffset + 'RunLengthArray'.length + 1;
  while (opening < source.length && _isWhitespace(source[opening])) {
    opening++;
  }
  if (opening >= source.length || source[opening] != 0x5b) {
    return source;
  }
  final int closing = source.indexOf(0x5d, opening + 1);
  if (closing < 0) {
    return source;
  }
  final String contents = String.fromCharCodes(Uint8List.sublistView(source, opening + 1, closing));
  final List<int> lengths = RegExp(r'-?\d+').allMatches(contents).map((match) => int.parse(match.group(0)!)).toList();
  if (lengths.isEmpty) {
    return source;
  }
  final int target = newLength + 1;
  final List<int> adjusted = <int>[];
  int remaining = target;
  for (final int length in lengths) {
    if (remaining <= 0) {
      break;
    }
    final int kept = length.clamp(0, remaining);
    adjusted.add(kept);
    remaining -= kept;
  }
  if (adjusted.isEmpty) {
    adjusted.add(target);
  } else if (remaining > 0) {
    adjusted[adjusted.length - 1] += remaining;
  }
  final BytesBuilder output = BytesBuilder(copy: false)
    ..add(Uint8List.sublistView(source, 0, opening + 1))
    ..add(' ${adjusted.join(' ')} '.codeUnits)
    ..add(Uint8List.sublistView(source, closing));
  return output.takeBytes();
}

/// Encodes [text] using the byte order found in [original].
Uint8List _encodeEngineString(String text, Uint8List original) {
  final bool littleEndian = original.length >= 2 && original[0] == 0xff && original[1] == 0xfe;
  final BytesBuilder bytes = BytesBuilder(copy: false)..add(littleEndian ? const <int>[0xff, 0xfe] : const <int>[0xfe, 0xff]);
  for (final int unit in '$text\r'.codeUnits) {
    bytes.add(littleEndian ? <int>[unit & 0xff, unit >> 8] : <int>[unit >> 8, unit & 0xff]);
  }
  return bytes.takeBytes();
}
