part of '../model.dart';

/// A rectangle in document pixel coordinates.
final class PsdRectangle {
  /// Top edge.
  final int top;

  /// Left edge.
  final int left;

  /// Bottom edge.
  final int bottom;

  /// Right edge.
  final int right;

  /// Creates a rectangle from its four PSD edges.
  const PsdRectangle({
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
  });

  /// Creates a rectangle whose origin is zero.
  const PsdRectangle.fromSize({required int width, required int height}) : this(top: 0, left: 0, bottom: height, right: width);

  /// Non-negative pixel width.
  int get width => (right - left).clamp(0, 0x7fffffff);

  /// Non-negative pixel height.
  int get height => (bottom - top).clamp(0, 0x7fffffff);
}

/// An opaque Photoshop image resource block.
final class PsdImageResource {
  /// Numeric resource identifier.
  final int id;

  /// Pascal-string resource name.
  final String name;

  /// Four-character block signature.
  final String signature;

  /// Uninterpreted resource payload.
  final Uint8List data;

  /// Creates a resource that can be preserved during a read/write cycle.
  const PsdImageResource({
    required this.id,
    required this.data,
    this.name = '',
    this.signature = '8BIM',
  });
}

/// An opaque additional-layer-information block.
final class PsdTaggedBlock {
  /// Four-character block key.
  final String key;

  /// Four-character block signature.
  final String signature;

  /// Uninterpreted block payload, without alignment padding.
  final Uint8List data;

  /// Creates a block that can be interpreted by clients or preserved verbatim.
  const PsdTaggedBlock({
    required this.key,
    required this.data,
    this.signature = '8BIM',
  });

  /// Whether the payload is opaque Intel-order TIFF data, unsuitable for PSD export.
  bool get isForeignByteOrder => signature == 'MIB8' || signature == '46B8';
}

/// Parsed layer-mask metadata.
final class PsdLayerMask {
  /// Bounds of channel `-2`.
  final PsdRectangle rectangle;

  /// Value used outside the mask bounds.
  final int defaultColor;

  /// Primary mask flags.
  final int flags;

  /// Bounds of channel `-3`, when present.
  final PsdRectangle? realRectangle;

  /// Real-mask flags, when present.
  final int? realFlags;

  /// Real-mask default value, when present.
  final int? realDefaultColor;

  /// Original payload for fields not interpreted by PsdKit.
  final Uint8List data;

  /// Creates layer-mask metadata while retaining its complete binary payload.
  const PsdLayerMask({
    required this.rectangle,
    required this.defaultColor,
    required this.flags,
    required this.data,
    this.realRectangle,
    this.realFlags,
    this.realDefaultColor,
  });
}

/// Uncompressed samples for one layer channel.
final class PsdChannel {
  /// Component id, where `-1` is transparency and `-2` is the user mask.
  final int id;

  /// Big-endian sample bytes in row-major order.
  final Uint8List? _data;

  /// Deferred sample cache, absent for an authored or eagerly decoded plane.
  final _PsdLazyChannel? _lazy;

  /// Preferred encoding when the document is written.
  final PsdCompression compression;

  /// Creates channel samples.
  const PsdChannel({
    required this.id,
    required Uint8List data,
    this.compression = PsdCompression.rle,
    // Keep the public named argument `data` for source compatibility.
    // ignore: prefer_initializing_formals
  }) : _data = data,
       _lazy = null;

  /// Creates a channel whose decoder is called at most once after a successful read.
  PsdChannel.lazy({required this.id, required Uint8List Function() decode, required this.compression}) : _data = null, _lazy = _PsdLazyChannel(decode: decode);

  /// Big-endian sample bytes, materializing this channel on first access.
  Uint8List get data => _data ?? _lazy!.data;

  /// Whether samples are already resident without invoking the decoder.
  bool get isDecoded => _data != null || _lazy!._data != null;
}

/// Caches a successful deferred decode without changing the channel's public model.
final class _PsdLazyChannel {
  /// Callback released after it has produced its owned sample buffer.
  Uint8List Function()? _decode;

  /// Materialized sample bytes.
  Uint8List? _data;

  /// Holds a decoder until the first sample access.
  _PsdLazyChannel({required this._decode});

  /// Resolves and caches the plane exactly once.
  Uint8List get data {
    if (_data == null) {
      _data = _decode!();
      _decode = null;
    }
    return _data!;
  }
}
