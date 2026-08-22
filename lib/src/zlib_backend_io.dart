import 'dart:io';
import 'dart:typed_data';

/// Decompresses a zlib stream on native Dart platforms.
Uint8List psdZlibDecode(Uint8List input) => Uint8List.fromList(zlib.decode(input));

/// Compresses bytes into a zlib stream on native Dart platforms.
Uint8List psdZlibEncode(Uint8List input) => Uint8List.fromList(zlib.encode(input));
