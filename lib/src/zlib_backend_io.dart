import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Decompresses a zlib stream without allowing more than [maxOutputBytes].
Uint8List psdZlibDecode(Uint8List input, {required int maxOutputBytes}) {
  final _PsdLimitedByteSink output = _PsdLimitedByteSink(maxOutputBytes);
  final ByteConversionSink decoder = zlib.decoder.startChunkedConversion(output);
  decoder
    ..add(input)
    ..close();
  return output.takeBytes();
}

/// Compresses bytes into a zlib stream on native Dart platforms.
Uint8List psdZlibEncode(Uint8List input) => Uint8List.fromList(zlib.encode(input));

/// Collects decompressed chunks while enforcing an allocation ceiling.
final class _PsdLimitedByteSink implements Sink<List<int>> {
  /// Maximum accepted byte count.
  final int _limit;

  /// Chunks accepted from the native zlib decoder.
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  /// Creates a sink capped at [_limit] bytes.
  _PsdLimitedByteSink(this._limit);

  /// Adds [chunk] unless it would exceed the configured output limit.
  @override
  void add(List<int> chunk) {
    if (chunk.length > _limit - _bytes.length) {
      throw FormatException('Zlib output exceeds the expected $_limit bytes');
    }
    _bytes.add(chunk);
  }

  /// Closes the sink after the decoder has emitted its final chunk.
  @override
  void close() {}

  /// Returns the bounded decompressed output.
  Uint8List takeBytes() => _bytes.takeBytes();
}
