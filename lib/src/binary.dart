import 'dart:typed_data';

import 'package:psdkit/src/exceptions.dart';

/// Bounds-checked big-endian input used by the PSD parser.
final class PsdBinaryReader {
  /// Bytes exposed by this reader.
  final Uint8List bytes;

  /// Absolute offset represented by local offset zero.
  final int baseOffset;

  /// Big-endian view used for numeric reads.
  final ByteData _data;

  /// Current position relative to [bytes].
  int _offset = 0;

  /// Creates a reader over [bytes].
  PsdBinaryReader(this.bytes, {this.baseOffset = 0}) : _data = ByteData.sublistView(bytes);

  /// Current local offset.
  int get offset => _offset;

  /// Bytes that have not been consumed.
  int get remaining => bytes.length - _offset;

  /// Whether the complete bounded input has been consumed.
  bool get isAtEnd => _offset == bytes.length;

  /// Reads an unsigned byte.
  int readUint8() {
    _require(1);
    return _data.getUint8(_offset++);
  }

  /// Reads a signed 16-bit integer.
  int readInt16() {
    _require(2);
    final int value = _data.getInt16(_offset);
    _offset += 2;
    return value;
  }

  /// Reads an unsigned 16-bit integer.
  int readUint16() {
    _require(2);
    final int value = _data.getUint16(_offset);
    _offset += 2;
    return value;
  }

  /// Reads a signed 32-bit integer.
  int readInt32() {
    _require(4);
    final int value = _data.getInt32(_offset);
    _offset += 4;
    return value;
  }

  /// Reads an unsigned 32-bit integer.
  int readUint32() {
    _require(4);
    final int value = _data.getUint32(_offset);
    _offset += 4;
    return value;
  }

  /// Reads an unsigned 64-bit integer.
  int readUint64() {
    _require(8);
    final int value = _data.getUint64(_offset);
    _offset += 8;
    return value;
  }

  /// Reads a signed 64-bit integer.
  int readInt64() {
    _require(8);
    final int value = _data.getInt64(_offset);
    _offset += 8;
    return value;
  }

  /// Reads a big-endian double-precision floating-point value.
  double readFloat64() {
    _require(8);
    final double value = _data.getFloat64(_offset);
    _offset += 8;
    return value;
  }

  /// Reads a fixed-length Latin-1 string.
  String readString(int length) {
    final Uint8List value = readBytes(length);
    return String.fromCharCodes(value);
  }

  /// Reads and copies [length] bytes.
  Uint8List readBytes(int length) {
    _require(length);
    final Uint8List value = Uint8List.sublistView(bytes, _offset, _offset + length);
    _offset += length;
    return Uint8List.fromList(value);
  }

  /// Reads a zero-copy view of the next [length] bytes.
  Uint8List readView(int length) {
    _require(length);
    final Uint8List value = Uint8List.sublistView(bytes, _offset, _offset + length);
    _offset += length;
    return value;
  }

  /// Creates a bounded reader for the next [length] bytes.
  PsdBinaryReader readReader(int length) {
    final int absoluteOffset = baseOffset + _offset;
    return PsdBinaryReader(readView(length), baseOffset: absoluteOffset);
  }

  /// Advances over [length] bytes.
  void skip(int length) {
    _require(length);
    _offset += length;
  }

  /// Reads a length after checking it is representable and in bounds.
  int readLength({required bool wide, String label = 'section'}) {
    final int value = wide ? readUint64() : readUint32();
    if (value > remaining) {
      throw PsdFormatException('$label length $value exceeds the $remaining remaining bytes', bytes, baseOffset + _offset);
    }
    return value;
  }

  /// Ensures that [length] bytes remain before a read or skip.
  void _require(int length) {
    if (length < 0 || length > remaining) {
      throw PsdFormatException('Unexpected end of file: need $length bytes, have $remaining', bytes, baseOffset + _offset);
    }
  }
}

/// Growable big-endian output used by the PSD writer.
final class PsdBinaryWriter {
  /// Accumulates encoded bytes without repeatedly copying the buffer.
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  /// Number of bytes written.
  int get length => _bytes.length;

  /// Writes an unsigned byte.
  void writeUint8(int value) => _bytes.add(<int>[value & 0xff]);

  /// Writes a signed 16-bit integer.
  void writeInt16(int value) => _writeNumber(2, (data) => data.setInt16(0, value));

  /// Writes an unsigned 16-bit integer.
  void writeUint16(int value) => _writeNumber(2, (data) => data.setUint16(0, value));

  /// Writes a signed 32-bit integer.
  void writeInt32(int value) => _writeNumber(4, (data) => data.setInt32(0, value));

  /// Writes an unsigned 32-bit integer.
  void writeUint32(int value) => _writeNumber(4, (data) => data.setUint32(0, value));

  /// Writes an unsigned 64-bit integer.
  void writeUint64(int value) => _writeNumber(8, (data) => data.setUint64(0, value));

  /// Writes a signed 64-bit integer.
  void writeInt64(int value) => _writeNumber(8, (data) => data.setInt64(0, value));

  /// Writes a big-endian double-precision floating-point value.
  void writeFloat64(double value) => _writeNumber(8, (data) => data.setFloat64(0, value));

  /// Writes a fixed-size character string.
  void writeString(String value) => writeBytes(value.codeUnits);

  /// Appends arbitrary bytes.
  void writeBytes(List<int> value) => _bytes.add(value);

  /// Writes zero padding.
  void writeZeros(int count) => _bytes.add(Uint8List(count));

  /// Writes either a 32-bit or 64-bit section length.
  void writeLength(int value, {required bool wide}) {
    if (wide) {
      writeUint64(value);
    } else {
      writeUint32(value);
    }
  }

  /// Returns all written bytes.
  Uint8List takeBytes() => _bytes.takeBytes();

  /// Writes a numeric value of [size] bytes through [set].
  void _writeNumber(int size, void Function(ByteData data) set) {
    final ByteData data = ByteData(size);
    set(data);
    _bytes.add(data.buffer.asUint8List());
  }
}
