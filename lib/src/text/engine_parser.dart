part of '../text.dart';

/// Maximum dictionary and array nesting accepted from untrusted engine data.
///
/// Photoshop writes far shallower structures; the bound keeps a hostile file
/// from exhausting the stack through the parser's recursion.
const int _maximumEngineDepth = 64;

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

/// Bounded parser for the PostScript subset used by Adobe `EngineData`.
final class _PsdEngineParser {
  /// Bytes being parsed.
  final Uint8List _bytes;

  /// Current byte offset.
  int _offset;

  /// Number of dictionaries and arrays currently open.
  int _depth = 0;

  /// Creates an engine-data parser.
  _PsdEngineParser({required this._bytes, this._offset = 0});

  /// Current byte offset.
  int get offset => _offset;

  /// Parses the single root value.
  Object? parse() {
    _skipTrivia();
    final Object? result = _readValue();
    _skipTrivia();
    return result;
  }

  /// Reads a literal string at the current offset.
  _PsdEngineString readLiteralString() {
    if (_offset >= _bytes.length || _bytes[_offset] != 0x28) {
      throw const FormatException('Expected EngineData string');
    }
    _offset++;
    int depth = 1;
    final BytesBuilder value = BytesBuilder(copy: false);
    while (_offset < _bytes.length) {
      final int byte = _bytes[_offset++];
      if (byte == 0x5c) {
        if (_offset >= _bytes.length) {
          throw const FormatException('Truncated EngineData escape');
        }
        final int escaped = _bytes[_offset++];
        if (escaped == 0x0a) {
          continue;
        }
        if (escaped == 0x0d) {
          if (_offset < _bytes.length && _bytes[_offset] == 0x0a) {
            _offset++;
          }
          continue;
        }
        if (escaped >= 0x30 && escaped <= 0x37) {
          int octal = escaped - 0x30;
          int count = 1;
          while (count < 3 && _offset < _bytes.length && _bytes[_offset] >= 0x30 && _bytes[_offset] <= 0x37) {
            octal = octal * 8 + _bytes[_offset++] - 0x30;
            count++;
          }
          value.addByte(octal & 0xff);
        } else {
          value.addByte(switch (escaped) {
            0x6e => 0x0a,
            0x72 => 0x0d,
            0x74 => 0x09,
            0x62 => 0x08,
            0x66 => 0x0c,
            _ => escaped,
          });
        }
      } else if (byte == 0x28) {
        depth++;
        value.addByte(byte);
      } else if (byte == 0x29) {
        if (--depth == 0) {
          return _PsdEngineString(bytes: value.takeBytes());
        }
        value.addByte(byte);
      } else {
        value.addByte(byte);
      }
    }
    throw const FormatException('Unterminated EngineData string');
  }

  /// Reads one engine-data value.
  Object? _readValue() {
    _skipTrivia();
    if (_offset >= _bytes.length) {
      throw const FormatException('Missing EngineData value');
    }
    if (_startsWith('<<')) {
      return _readDictionary();
    }
    if (_bytes[_offset] == 0x5b) {
      return _readArray();
    }
    if (_bytes[_offset] == 0x28) {
      return readLiteralString();
    }
    if (_bytes[_offset] == 0x2f) {
      return _PsdEngineName(value: _readName());
    }
    final String token = _readToken();
    if (token == 'true') {
      return true;
    }
    if (token == 'false') {
      return false;
    }
    if (token == 'null') {
      return null;
    }
    return num.tryParse(token) ?? token;
  }

  /// Reads a `<< ... >>` dictionary.
  _PsdEngineDictionary _readDictionary() {
    _enter();
    _offset += 2;
    final Map<String, Object?> values = <String, Object?>{};
    while (true) {
      _skipTrivia();
      if (_startsWith('>>')) {
        _offset += 2;
        _depth--;
        return _PsdEngineDictionary(values: values);
      }
      if (_offset >= _bytes.length || _bytes[_offset] != 0x2f) {
        throw const FormatException('Expected EngineData dictionary key');
      }
      final String key = _readName();
      values[key] = _readValue();
    }
  }

  /// Reads a `[ ... ]` array.
  List<Object?> _readArray() {
    _enter();
    _offset++;
    final List<Object?> values = <Object?>[];
    while (true) {
      _skipTrivia();
      if (_offset >= _bytes.length) {
        throw const FormatException('Unterminated EngineData array');
      }
      if (_bytes[_offset] == 0x5d) {
        _offset++;
        _depth--;
        return values;
      }
      values.add(_readValue());
    }
  }

  /// Opens one nesting level, rejecting input that would exhaust the stack.
  void _enter() {
    if (++_depth > _maximumEngineDepth) {
      throw const FormatException('EngineData nesting exceeds the supported depth');
    }
  }

  /// Reads a slash-prefixed PostScript name.
  String _readName() {
    _offset++;
    final int start = _offset;
    while (_offset < _bytes.length && !_isDelimiter(_bytes[_offset])) {
      _offset++;
    }
    return String.fromCharCodes(Uint8List.sublistView(_bytes, start, _offset));
  }

  /// Reads a bare token.
  String _readToken() {
    final int start = _offset;
    while (_offset < _bytes.length && !_isDelimiter(_bytes[_offset])) {
      _offset++;
    }
    if (start == _offset) {
      throw const FormatException('Empty EngineData token');
    }
    return String.fromCharCodes(Uint8List.sublistView(_bytes, start, _offset));
  }

  /// Skips spaces and percent comments.
  void _skipTrivia() {
    while (_offset < _bytes.length) {
      if (_isWhitespace(_bytes[_offset])) {
        _offset++;
      } else if (_bytes[_offset] == 0x25) {
        while (_offset < _bytes.length && _bytes[_offset] != 0x0a && _bytes[_offset] != 0x0d) {
          _offset++;
        }
      } else {
        return;
      }
    }
  }

  /// Whether upcoming bytes equal [value].
  bool _startsWith(String value) {
    if (_offset + value.length > _bytes.length) {
      return false;
    }
    for (int index = 0; index < value.length; index++) {
      if (_bytes[_offset + index] != value.codeUnitAt(index)) {
        return false;
      }
    }
    return true;
  }
}

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
