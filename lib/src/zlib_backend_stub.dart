import 'dart:typed_data';

/// Reports that the current Dart platform has no synchronous zlib codec.
Uint8List psdZlibDecode(Uint8List input, {required int maxOutputBytes}) => throw UnsupportedError('ZIP-compressed PSD data requires a Dart platform with dart:io support');

/// Reports that the current Dart platform has no synchronous zlib codec.
Uint8List psdZlibEncode(Uint8List input) => throw UnsupportedError('ZIP-compressed PSD data requires a Dart platform with dart:io support');
