part of '../image_resources.dart';

/// Semantic or explicitly opaque payload of one image-resource block.
sealed class PsdImageResourceData {
  /// Creates an image-resource data value.
  const PsdImageResourceData();

  /// Resource identifier accepted by this value.
  int get resourceId;
}

/// Bytes belonging to an unknown or private resource format.
final class PsdRawImageResource extends PsdImageResourceData {
  /// Resource identifier.
  @override
  final int resourceId;

  /// Uninterpreted resource bytes.
  final Uint8List data;

  /// Creates an opaque image-resource value.
  const PsdRawImageResource({required this.resourceId, required this.data});
}

/// Document metadata whose external binary standard is retained verbatim.
final class PsdBinaryMetadataResource extends PsdImageResourceData {
  /// Resource identifier.
  @override
  final int resourceId;

  /// Complete IPTC, EXIF, digest, or platform payload.
  final Uint8List data;

  /// Creates a binary metadata resource.
  const PsdBinaryMetadataResource({required this.resourceId, required this.data});
}

/// A one-byte image-resource value.
final class PsdByteImageResource extends PsdImageResourceData {
  /// Resource identifier.
  @override
  final int resourceId;

  /// Unsigned stored value.
  final int value;

  /// Creates a byte resource.
  const PsdByteImageResource({required this.resourceId, required this.value});
}

/// A two-byte image-resource value.
final class PsdShortImageResource extends PsdImageResourceData {
  /// Resource identifier.
  @override
  final int resourceId;

  /// Unsigned stored value.
  final int value;

  /// Creates a short-integer resource.
  const PsdShortImageResource({required this.resourceId, required this.value});
}

/// A signed four-byte image-resource value.
final class PsdIntegerImageResource extends PsdImageResourceData {
  /// Resource identifier.
  @override
  final int resourceId;

  /// Signed stored value.
  final int value;

  /// Creates an integer resource.
  const PsdIntegerImageResource({required this.resourceId, required this.value});
}

/// A sequence of one-byte values consuming the complete payload.
final class PsdByteListImageResource extends PsdImageResourceData {
  /// Resource identifier.
  @override
  final int resourceId;

  /// Ordered unsigned byte values.
  final List<int> values;

  /// Creates a byte-list resource.
  const PsdByteListImageResource({required this.resourceId, required this.values});
}

/// A sequence of fixed-width unsigned integers.
final class PsdIntegerListImageResource extends PsdImageResourceData {
  /// Resource identifier.
  @override
  final int resourceId;

  /// Ordered integer values.
  final List<int> values;

  /// Bytes occupied by each value, either two or four.
  final int valueBytes;

  /// Count prefix representation.
  final PsdImageResourceListLayout layout;

  /// Creates an integer-list resource.
  const PsdIntegerListImageResource({required this.resourceId, required this.values, required this.valueBytes, this.layout = PsdImageResourceListLayout.uncounted});
}

/// A list of Pascal or UTF-16 image-resource strings.
final class PsdStringListImageResource extends PsdImageResourceData {
  /// Resource identifier.
  @override
  final int resourceId;

  /// Ordered decoded strings.
  final List<String> values;

  /// Whether strings use Photoshop's UTF-16 representation.
  final bool unicode;

  /// Creates a string-list resource.
  const PsdStringListImageResource({required this.resourceId, required this.values, required this.unicode});
}

/// A single Unicode or UTF-8 image-resource string.
final class PsdTextImageResource extends PsdImageResourceData {
  /// Resource identifier.
  @override
  final int resourceId;

  /// Decoded text.
  final String value;

  /// Whether the stored representation is UTF-8 rather than PSD UTF-16.
  final bool utf8;

  /// Original bytes used to retain an unchanged UTF-8 packet exactly.
  final Uint8List? _sourceData;

  /// Original decoded text corresponding to [_sourceData].
  final String? _sourceValue;

  /// Creates an editable text resource.
  PsdTextImageResource({required this.resourceId, required this.value, required this.utf8}) : _sourceData = null, _sourceValue = null;

  /// Creates decoded text while retaining its exact original byte representation.
  PsdTextImageResource._decoded({required this.resourceId, required this.value, required this.utf8, required this._sourceData}) : _sourceValue = value;
}
