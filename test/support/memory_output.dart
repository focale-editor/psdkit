import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';

/// Stores random-access output in a growable test buffer.
final class MemoryRandomAccessOutput implements PsdRandomAccessOutput {
  /// Mutable backing bytes.
  Uint8List _bytes = Uint8List(0);

  /// Current cursor.
  int _position = 0;

  /// Immutable view of the written bytes.
  Uint8List get bytes => _bytes.asUnmodifiableView();

  @override
  int get position => _position;

  @override
  Future<void> flush() async {}

  @override
  Future<void> setPosition(int position) async {
    if (position < 0 || position > _bytes.lengthInBytes) {
      throw RangeError.range(position, 0, _bytes.lengthInBytes);
    }
    _position = position;
  }

  @override
  Future<void> truncate(int length) async {
    if (length < 0) {
      throw RangeError.value(length);
    }
    final Uint8List resized = Uint8List(length);
    resized.setRange(0, length.clamp(0, _bytes.lengthInBytes), _bytes);
    _bytes = resized;
    _position = _position.clamp(0, length);
  }

  @override
  Future<void> write(Uint8List bytes) async {
    final int end = _position + bytes.lengthInBytes;
    if (end > _bytes.lengthInBytes) {
      final Uint8List grown = Uint8List(end);
      grown.setRange(0, _bytes.lengthInBytes, _bytes);
      _bytes = grown;
    }
    _bytes.setRange(_position, end, bytes);
    _position = end;
  }
}
