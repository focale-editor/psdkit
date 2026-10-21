part of '../codec.dart';

/// Zero bytes that ended the layer info a list of layers was decoded from.
final Expando<int> _layerInfoPadding = Expando<int>('PSD layer info padding');

/// The compressed bytes samples were decoded from, kept to write them back unchanged.
///
/// Encoders differ in how they split PackBits runs and deflate streams, so
/// re-encoding pixels another application wrote, such as ImageReady, changes
/// the file even when no sample changed. Decoded sample buffers remember their
/// source bytes by identity, and a checksum taken at decoding detects samples
/// modified in place since.
final class _SourceEncoding {
  /// Source encoding of each decoded buffer, keyed by its first channel.
  static final Expando<_SourceEncoding> _encodings = Expando<_SourceEncoding>('PSD source encoding');

  /// The decoded buffers, in order.
  final List<Uint8List> channels;

  /// Checksums of [channels] when they were decoded.
  final List<int> checksums;

  /// Width, height, bit depth and whether this is a merged stream.
  final (int, int, int, bool) geometry;

  /// Compression of [payload].
  final PsdCompression compression;

  /// Whether RLE row lengths in [payload] are PSB-wide.
  final bool wideRowLengths;

  /// Compressed bytes, without the compression marker.
  final Uint8List payload;

  /// Creates a remembered encoding.
  _SourceEncoding({required this.geometry, required this.channels, required this.checksums, required this.compression, required this.wideRowLengths, required this.payload});

  /// Remembers that [channels] were decoded from [payload].
  ///
  /// Raw samples gain nothing, since writing them again gives the same bytes.
  static void remember(List<Uint8List> channels, {required (int, int, int, bool) geometry, required PsdCompression compression, required Uint8List payload, bool wideRowLengths = false}) {
    if (channels.isEmpty || compression == PsdCompression.raw) {
      return;
    }
    _encodings[channels.first] = _SourceEncoding(
      geometry: geometry,
      channels: List<Uint8List>.of(channels),
      checksums: [for (final Uint8List channel in channels) _checksum(channel)],
      compression: compression,
      wideRowLengths: wideRowLengths,
      // A copy, so the rest of the source file can be released.
      payload: Uint8List.fromList(payload),
    );
  }

  /// Returns the source bytes of [channels] when they are unchanged and written the same way.
  static Uint8List? reuse(List<Uint8List> channels, {required (int, int, int, bool) geometry, required PsdCompression compression, required bool wideRowLengths}) {
    if (channels.isEmpty) {
      return null;
    }
    final _SourceEncoding? source = _encodings[channels.first];
    if (source == null || source.geometry != geometry || source.compression != compression || source.wideRowLengths != wideRowLengths || source.channels.length != channels.length) {
      return null;
    }
    for (int index = 0; index < channels.length; index++) {
      if (!identical(source.channels[index], channels[index]) || source.checksums[index] != _checksum(channels[index])) {
        return null;
      }
    }
    return source.payload;
  }

  /// FNV-1a checksum of [bytes], combined with their length.
  static int _checksum(Uint8List bytes) {
    int hash = 0x811c9dc5 ^ bytes.length;
    for (final int value in bytes) {
      hash = ((hash ^ value) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}
