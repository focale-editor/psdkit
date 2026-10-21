part of '../adjustments.dart';

/// A single unsigned 16-bit adjustment value.
final class PsdSingleValueAdjustment extends PsdAdjustment {
  /// Semantic family, either posterize or threshold.
  @override
  final PsdAdjustmentType type;

  /// Stored value.
  final int value;

  /// Uninterpreted bytes following the value.
  final Uint8List trailingData;

  /// Creates a posterize or threshold adjustment.
  PsdSingleValueAdjustment({required this.type, required this.value, Uint8List? trailingData}) : trailingData = trailingData ?? Uint8List(0) {
    if (type != PsdAdjustmentType.posterize && type != PsdAdjustmentType.threshold) {
      throw ArgumentError.value(type, 'type', 'must be posterize or threshold');
    }
  }

  @override
  String get blockKey => type == PsdAdjustmentType.posterize ? 'post' : 'thrs';
}

/// An invert adjustment, whose `nvrt` payload is normally empty.
final class PsdInvertAdjustment extends PsdAdjustment {
  /// Uninterpreted payload retained for unusual Photoshop variants.
  final Uint8List data;

  /// Creates an invert adjustment.
  PsdInvertAdjustment({Uint8List? data}) : data = data ?? Uint8List(0);

  @override
  String get blockKey => 'nvrt';

  @override
  PsdAdjustmentType get type => PsdAdjustmentType.invert;
}

/// A fill or adjustment represented by an Adobe action descriptor.
final class PsdDescriptorAdjustment extends PsdAdjustment {
  /// Four-character tagged-block key.
  @override
  final String blockKey;

  /// Semantic adjustment family.
  @override
  final PsdAdjustmentType type;

  /// Block-specific version preceding the descriptor, when present.
  final int? version;

  /// Action-descriptor version, normally 16.
  final int descriptorVersion;

  /// Complete editable action descriptor.
  final PsDescriptor descriptor;

  /// Uninterpreted bytes following the descriptor.
  final Uint8List trailingData;

  /// Creates a descriptor-backed adjustment.
  PsdDescriptorAdjustment({
    required this.blockKey,
    required this.type,
    this.version,
    this.descriptorVersion = 16,
    required this.descriptor,
    Uint8List? trailingData,
  }) : trailingData = trailingData ?? Uint8List(0);

  /// Typed paint of a solid-color, gradient, or pattern fill layer.
  PsdFillContent? get fill => switch (PsdFillKind.fromAdjustmentType(type)) {
    final PsdFillKind kind => PsdFillContent.fromDescriptor(kind, descriptor),
    null => null,
  };

  /// Returns a copy whose descriptor property [key] is [value].
  PsdDescriptorAdjustment withProperty(String key, PsDescriptorValue value) => PsdDescriptorAdjustment(
    blockKey: blockKey,
    type: type,
    version: version,
    descriptorVersion: descriptorVersion,
    descriptor: descriptor.withValue(key, value),
    trailingData: trailingData,
  );
}

/// A recognized adjustment whose undocumented structure is retained verbatim.
final class PsdRawAdjustment extends PsdAdjustment {
  /// Four-character tagged-block key.
  @override
  final String blockKey;

  /// Semantic adjustment family.
  @override
  final PsdAdjustmentType type;

  /// Exact block payload.
  final Uint8List data;

  /// Creates a loss-preserving view of an unsupported adjustment variant.
  const PsdRawAdjustment({required this.blockKey, required this.type, required this.data});
}
