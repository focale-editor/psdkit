part of '../smart_objects.dart';

/// Reads a one-byte-length Pascal string and exact alignment bytes.
({String value, Uint8List padding}) _readPascalString(PsBinaryReader reader, {required int alignment}) {
  final int length = reader.readUint8();
  final String value = reader.readString(length);
  return (value: value, padding: reader.readBytes(_pascalPaddingLength(length, alignment: alignment)));
}

/// Writes a Pascal [value] followed by its preserved [padding].
void _writePascalString(PsBinaryWriter writer, String value, Uint8List padding, {required int alignment}) {
  if (value.length > 255 || value.codeUnits.any((unit) => unit > 0xff)) {
    throw const PsWriteException(message: 'Pascal strings must contain at most 255 one-byte characters');
  }
  final int expectedPadding = _pascalPaddingLength(value.length, alignment: alignment);
  if (padding.length != expectedPadding) {
    throw PsWriteException(message: 'Pascal string requires $expectedPadding padding bytes, received ${padding.length}');
  }
  writer
    ..writeUint8(value.length)
    ..writeString(value)
    ..writeBytes(padding);
}

/// Returns padding required after a Pascal string of [length].
int _pascalPaddingLength(int length, {required int alignment}) => (alignment - ((length + 1) % alignment)) % alignment;

/// Returns the four-byte alignment padding after an entry body of [length].
int _entryPaddingLength(int length) => (4 - (length % 4)) % 4;

/// Reads a length-prefixed UTF-16 string and removes one terminal NUL.
({String value, bool terminalNull}) _readUnicodeString(PsBinaryReader reader) {
  final int count = reader.readUint32();
  if (count > reader.remaining ~/ 2) {
    throw PsFormatException(message: 'Truncated linked-resource Unicode string', source: reader.bytes, offset: reader.offset);
  }
  final List<int> units = <int>[for (int index = 0; index < count; index++) reader.readUint16()];
  final bool terminalNull = units.isNotEmpty && units.last == 0;
  return (value: String.fromCharCodes(terminalNull ? units.sublist(0, units.length - 1) : units), terminalNull: terminalNull);
}

/// Writes a length-prefixed UTF-16 [value].
void _writeUnicodeString(PsBinaryWriter writer, String value, {required bool terminalNull}) {
  writer.writeUint32(value.codeUnits.length + (terminalNull ? 1 : 0));
  value.codeUnits.forEach(writer.writeUint16);
  if (terminalNull) {
    writer.writeUint16(0);
  }
}

/// Creates a zero-copy bounded reader for the next [length] bytes.
PsBinaryReader _readView(PsBinaryReader reader, int length) {
  final Uint8List bytes = _readByteView(reader, length);
  return PsBinaryReader(bytes: bytes, baseOffset: reader.baseOffset + reader.offset - length);
}

/// Returns a zero-copy view of the next [length] bytes and advances [reader].
Uint8List _readByteView(PsBinaryReader reader, int length) {
  if (length < 0 || length > reader.remaining) {
    throw PsFormatException(message: 'Unexpected end of linked resource', source: reader.bytes, offset: reader.baseOffset + reader.offset);
  }
  final Uint8List bytes = Uint8List.sublistView(reader.bytes, reader.offset, reader.offset + length);
  reader.skip(length);
  return bytes;
}

/// Writes a required four-character one-byte code.
void _writeFourCharacters(PsBinaryWriter writer, String value, String label) {
  if (value.length != 4 || value.codeUnits.any((unit) => unit > 0xff)) {
    throw PsWriteException(message: '$label must contain four one-byte characters');
  }
  writer.writeString(value);
}
