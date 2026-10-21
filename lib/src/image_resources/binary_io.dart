part of '../image_resources.dart';

/// Reads Pascal strings until the resource ends.
List<String> _readPascalStrings(PsBinaryReader reader) {
  final List<String> result = <String>[];
  while (!reader.isAtEnd) {
    result.add(reader.readString(reader.readUint8()));
  }
  return result;
}

/// Writes one unpadded one-byte Pascal string.
void _writePascalString(PsBinaryWriter writer, String value) {
  final List<int> bytes = _oneByteString(value, 255);
  writer
    ..writeUint8(bytes.length)
    ..writeBytes(bytes);
}

/// Reads UTF-16 strings until the resource ends.
List<String> _readUnicodeStrings(PsBinaryReader reader) {
  final List<String> result = <String>[];
  while (!reader.isAtEnd) {
    result.add(_readUnicodeString(reader));
  }
  return result;
}

/// Reads a length-prefixed big-endian UTF-16 string.
String _readUnicodeString(PsBinaryReader reader) {
  final int length = reader.readUint32();
  if (length > reader.remaining ~/ 2) {
    throw const PsFormatException(message: 'Truncated image-resource Unicode string');
  }
  return String.fromCharCodes(<int>[for (int index = 0; index < length; index++) reader.readUint16()]);
}

/// Writes a length-prefixed big-endian UTF-16 string.
void _writeUnicodeString(PsBinaryWriter writer, String value) {
  writer.writeUint32(value.codeUnits.length);
  value.codeUnits.forEach(writer.writeUint16);
}

/// Converts [value] to one-byte characters, rejecting unsupported code units.
List<int> _oneByteString(String value, int maximumLength) {
  if (value.length > maximumLength || value.codeUnits.any((unit) => unit > 0xff)) {
    throw PsWriteException(message: 'Image-resource string must contain at most $maximumLength one-byte characters');
  }
  return value.codeUnits;
}

/// Reads a four-character ASCII signature at [offset], when available.
String? _asciiAt(Uint8List bytes, int offset) => offset < 0 || offset + 4 > bytes.length ? null : String.fromCharCodes(Uint8List.sublistView(bytes, offset, offset + 4));

/// Validates that [value] fits an unsigned integer of [bits].
void _requireUnsigned(int value, int bits, String label) {
  final int maximum = (BigInt.one << bits).toInt() - 1;
  if (value < 0 || value > maximum) {
    throw PsWriteException(message: '$label $value does not fit in $bits bits');
  }
}
