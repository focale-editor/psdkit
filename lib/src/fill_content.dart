import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:psdkit/src/adjustments.dart';
import 'package:psdkit/src/model.dart';

part 'fill_content/paints.dart';
part 'fill_content/shape_stroke.dart';

/// Identifies the paint used by a fill layer, shape fill, or shape stroke.
enum PsdFillKind {
  /// A single color.
  solidColor(blockKey: 'SoCo', layerClassId: 'solidColorLayer', adjustmentType: PsdAdjustmentType.solidColor),

  /// A gradient.
  gradient(blockKey: 'GdFl', layerClassId: 'gradientLayer', adjustmentType: PsdAdjustmentType.gradientFill),

  /// A repeated pattern.
  pattern(blockKey: 'PtFl', layerClassId: 'patternLayer', adjustmentType: PsdAdjustmentType.patternFill);

  /// Tagged-block key of a fill layer using this paint.
  final String blockKey;

  /// Descriptor class used when this paint is nested in a shape stroke.
  final String layerClassId;

  /// Matching fill-layer adjustment family.
  final PsdAdjustmentType adjustmentType;

  /// Creates a paint kind stored under the given identifiers.
  const PsdFillKind({required this.blockKey, required this.layerClassId, required this.adjustmentType});

  /// Returns the paint kind stored under a fill-layer block [key].
  static PsdFillKind? fromBlockKey(String key) {
    for (final PsdFillKind kind in values) {
      if (kind.blockKey == key) {
        return kind;
      }
    }
    return null;
  }

  /// Returns the paint kind of a fill-layer adjustment [type].
  static PsdFillKind? fromAdjustmentType(PsdAdjustmentType type) {
    for (final PsdFillKind kind in values) {
      if (kind.adjustmentType == type) {
        return kind;
      }
    }
    return null;
  }

  /// Returns the paint kind of a nested shape-stroke descriptor [classId].
  static PsdFillKind? fromLayerClassId(String classId) {
    for (final PsdFillKind kind in values) {
      if (kind.layerClassId == classId) {
        return kind;
      }
    }
    return null;
  }
}

/// Typed view over the paint descriptor of a fill layer, shape, or stroke.
///
/// The complete [descriptor] remains authoritative, so properties that are not
/// modeled here survive editing.
sealed class PsdFillContent {
  /// Complete paint descriptor.
  final PsDescriptor descriptor;

  /// Creates a view over [descriptor].
  const PsdFillContent({required this.descriptor});

  /// Creates the typed view matching [kind].
  factory PsdFillContent.fromDescriptor(PsdFillKind kind, PsDescriptor descriptor) => switch (kind) {
    PsdFillKind.solidColor => PsdSolidColorFill(descriptor: descriptor),
    PsdFillKind.gradient => PsdGradientFill(descriptor: descriptor),
    PsdFillKind.pattern => PsdPatternFill(descriptor: descriptor),
  };

  /// Decodes a `vscg` shape-fill payload, returning `null` when malformed.
  static PsdFillContent? tryDecodeShapeFill(Uint8List data) {
    if (data.length < 8) {
      return null;
    }
    final PsdFillKind? kind = PsdFillKind.fromBlockKey(String.fromCharCodes(data, 0, 4));
    if (kind == null) {
      return null;
    }
    try {
      final PsVersionedDescriptor decoded = PsVersionedDescriptorCodec.decodePrefix(Uint8List.sublistView(data, 4), expectedVersion: 16).value;
      return PsdFillContent.fromDescriptor(kind, decoded.descriptor);
    } on FormatException {
      return null;
    }
  }

  /// Paint family of this content.
  PsdFillKind get kind;

  /// Converts this content to a fill-layer adjustment.
  PsdDescriptorAdjustment toAdjustment() => PsdDescriptorAdjustment(blockKey: kind.blockKey, type: kind.adjustmentType, descriptor: descriptor);

  /// Encodes this content as a `vscg` shape-fill block.
  PsdTaggedBlock toShapeFillBlock() => PsdTaggedBlock(
    key: 'vscg',
    data:
        (PsBinaryWriter()
              ..writeString(kind.blockKey)
              ..writeBytes(PsVersionedDescriptorCodec.encode(PsVersionedDescriptor(descriptor: descriptor))))
            .takeBytes(),
  );
}
