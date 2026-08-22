import 'dart:typed_data';

import 'package:zcodec/zcodec.dart';

/// Decompresses a zlib stream without allowing more than [maxOutputBytes].
Uint8List psdZlibDecode(Uint8List input, {required int maxOutputBytes}) => const ZlibCodec().decode(input, maxOutputBytes: maxOutputBytes);

/// Compresses bytes into a zlib stream on native Dart platforms.
Uint8List psdZlibEncode(Uint8List input) => Uint8List.fromList(const ZlibCodec().encode(input));
