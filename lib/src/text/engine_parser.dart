part of '../text.dart';

/// Removes the Photoshop terminator from a descriptor or engine string.
String _withoutTerminalNull(String value) => value.endsWith('\u0000') ? value.substring(0, value.length - 1) : value;

/// A dictionary parsed from Adobe text-engine data.
final class _PsdEngineDictionary {
  /// Ordered values indexed by PostScript name.
  final Map<String, Object?> values;

  /// Creates an engine dictionary.
  const _PsdEngineDictionary({required this.values});

  /// Returns the value associated with [key].
  Object? operator [](String key) => values[key];
}

/// A byte string parsed from Adobe text-engine data.
final class _PsdEngineString {
  /// Unescaped string bytes.
  final Uint8List bytes;

  /// Creates a binary engine string.
  const _PsdEngineString({required this.bytes});
}

/// A PostScript name used as a dictionary value.
final class _PsdEngineName {
  /// Name without its leading slash.
  final String value;

  /// Creates an engine name.
  const _PsdEngineName({required this.value});
}

/// Adapts the shared EngineData reader to Photoshop's private editing nodes.
final class _PsdEngineParser {
  /// Shared parser retaining Photoshop's historical duplicate-key policy.
  final PsEngineReader _reader;

  /// Creates a parser at an optional absolute byte position.
  _PsdEngineParser({required Uint8List bytes, int offset = 0}) : _reader = PsEngineReader.view(bytes: bytes, offset: offset, allowDuplicateKeys: true);

  /// Current absolute source position.
  int get offset => _reader.offset;

  /// Reads one root while retaining the existing tolerant trailing-data policy.
  Object? parse() => _privateEngineValue(_reader.readRoot(requireEnd: false));

  /// Reads one literal string without normalizing its binary UTF-16 bytes.
  _PsdEngineString readLiteralString() => _privateEngineValue(_reader.readLiteralString())! as _PsdEngineString;
}

/// Converts immutable shared nodes into the private mutable editing structure.
Object? _privateEngineValue(PsEngineValue value) => switch (value) {
  PsEngineDictionary(:final values) => _PsdEngineDictionary(values: {for (final MapEntry<String, PsEngineValue> entry in values.entries) entry.key: _privateEngineValue(entry.value)}),
  PsEngineArray(:final values) => [for (final PsEngineValue entry in values) _privateEngineValue(entry)],
  PsEngineString(:final bytes) => _PsdEngineString(bytes: bytes),
  PsEngineName(:final value) => _PsdEngineName(value: value),
  PsEngineNumber(:final value) => value,
  PsEngineBoolean(:final value) => value,
  PsEngineNull() => null,
  // Preserve the legacy parser's scalar fallback for existing PSD callers.
  PsEngineToken(:final value) => num.tryParse(value) ?? value,
};

/// Removes the required final paragraph mark from an EngineData editor string.
String _withoutEngineTerminator(String value) {
  final String withoutNull = _withoutTerminalNull(value);
  return withoutNull.endsWith('\r') ? withoutNull.substring(0, withoutNull.length - 1) : withoutNull;
}

/// Converts private parser nodes into immutable public values.
Object? _publicEngineValue(Object? value) {
  if (value is _PsdEngineDictionary) {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final MapEntry<String, Object?> entry in value.values.entries) entry.key: _publicEngineValue(entry.value),
    });
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(<Object?>[
      for (final Object? entry in value) _publicEngineValue(entry),
    ]);
  }
  if (value is _PsdEngineString) {
    return _decodeEngineString(value) ?? Uint8List.fromList(value.bytes);
  }
  if (value is _PsdEngineName) {
    return PsdTextEngineName(value: value.value);
  }
  return value;
}

/// Decodes a binary Adobe engine string, including its byte-order mark.
String? _decodeEngineString(Object? value) {
  if (value is! _PsdEngineString) {
    return null;
  }
  final Uint8List bytes = value.bytes;
  if (bytes.length >= 2 && ((bytes[0] == 0xfe && bytes[1] == 0xff) || (bytes[0] == 0xff && bytes[1] == 0xfe))) {
    final bool littleEndian = bytes[0] == 0xff;
    final List<int> units = <int>[];
    for (int index = 2; index + 1 < bytes.length; index += 2) {
      units.add(littleEndian ? bytes[index] | bytes[index + 1] << 8 : bytes[index] << 8 | bytes[index + 1]);
    }
    return String.fromCharCodes(units);
  }
  return String.fromCharCodes(bytes);
}

/// Whether [source] contains [name] followed by a name delimiter.
bool _matchesName(Uint8List source, int start, String name) {
  if (start + name.length > source.length) {
    return false;
  }
  for (int index = 0; index < name.length; index++) {
    if (source[start + index] != name.codeUnitAt(index)) {
      return false;
    }
  }
  final int end = start + name.length;
  return end == source.length || _isDelimiter(source[end]);
}

/// Finds a slash-prefixed [name] outside literal strings.
int _findName(Uint8List source, String name, {int start = 0}) {
  int index = start;
  while (index < source.length) {
    if (source[index] == 0x28) {
      index = _skipLiteralString(source, index);
    } else if (source[index] == 0x2f && _matchesName(source, index + 1, name)) {
      return index;
    } else {
      index++;
    }
  }
  return -1;
}

/// Skips a complete PostScript literal string starting at [offset].
int _skipLiteralString(Uint8List source, int offset) {
  try {
    final _PsdEngineParser parser = _PsdEngineParser(bytes: source, offset: offset);
    parser.readLiteralString();
    return parser.offset;
  } on FormatException {
    return source.length;
  }
}

/// Whether [byte] is PostScript whitespace.
bool _isWhitespace(int byte) => byte == 0 || byte == 9 || byte == 10 || byte == 12 || byte == 13 || byte == 32;

/// Whether [byte] ends a PostScript name or bare token.
bool _isDelimiter(int byte) =>
    _isWhitespace(byte) || byte == 0x28 || byte == 0x29 || byte == 0x3c || byte == 0x3e || byte == 0x5b || byte == 0x5d || byte == 0x7b || byte == 0x7d || byte == 0x2f || byte == 0x25;

/// Escapes binary [value] for a PostScript literal string.
Uint8List _escapePostScript(Uint8List value) {
  final BytesBuilder bytes = BytesBuilder(copy: false);
  for (final int byte in value) {
    if (byte == 0x28 || byte == 0x29 || byte == 0x5c) {
      bytes.addByte(0x5c);
    }
    bytes.addByte(byte);
  }
  return bytes.takeBytes();
}
