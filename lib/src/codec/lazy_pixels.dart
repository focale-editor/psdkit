part of '../codec.dart';

/// Accounts retained decoded samples across every plane of one document.
final class _PsdDecodeBudget {
  /// Maximum number of materialized sample bytes.
  final int maximum;

  /// Bytes retained by successful decodes.
  int _used = 0;

  /// Starts one independent document allocation budget.
  _PsdDecodeBudget({required this.maximum}) {
    if (maximum < 0) {
      throw ArgumentError.value(maximum, 'maxTotalDecodedBytes', 'must be nonnegative');
    }
  }

  /// Checks arithmetic before multiplication or allocation, outside recovery paths.
  int checkGeometry(int width, int height, int depth, int channels, int perImageLimit) {
    final int rowBytes = psdRowBytes(width, depth);
    final int remaining = maximum - _used;
    final int limit = remaining < perImageLimit ? remaining : perImageLimit;
    if (limit < 0 || channels < 1 || height < 0 || rowBytes < 0 || (rowBytes > 0 && height > limit ~/ channels ~/ rowBytes)) {
      throw const PsFormatException(message: 'Decoded samples exceed the channel or aggregate memory limit');
    }
    return rowBytes * height * channels;
  }

  /// Charges samples only after successful decoding.
  void commit(int size) => _used += size;
}

/// Defers the single composite stream until a merged plane or its list is read.
final class _PsdLazyMergedImage extends ListBase<Uint8List> {
  /// Decoder released after successful materialization or explicit recovery.
  List<Uint8List> Function()? _decode;

  /// Cached merged-image planes.
  List<Uint8List>? _samples;

  /// Creates a list whose metadata owner already knows the declared channel count.
  _PsdLazyMergedImage({required this._decode});

  /// Materializes the complete merged stream, which cannot be split before inflation.
  List<Uint8List> get _value {
    if (_samples == null) {
      _samples = _decode!();
      _decode = null;
    }
    return _samples!;
  }

  @override
  int get length => _value.length;

  @override
  set length(int value) => throw UnsupportedError('Merged channel lists cannot be resized');

  @override
  Uint8List operator [](int index) => _value[index];

  @override
  void operator []=(int index, Uint8List value) => throw UnsupportedError('Replace merged planes in a new document');
}
