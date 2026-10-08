import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:psdkit/src/adjustments.dart';
import 'package:psdkit/src/model.dart';

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

/// A solid-color paint.
final class PsdSolidColorFill extends PsdFillContent {
  /// Creates a view over a solid-color [descriptor].
  const PsdSolidColorFill({required super.descriptor});

  /// Creates a solid-color paint.
  factory PsdSolidColorFill.create({required PsColor color}) => PsdSolidColorFill(
    descriptor: PsDescriptor(
      name: '\u0000',
      classId: 'null',
      items: [
        PsDescriptorItem(
          key: 'Clr ',
          value: PsObjectValue(value: color.descriptor),
        ),
      ],
    ),
  );

  @override
  PsdFillKind get kind => PsdFillKind.solidColor;

  /// Paint color, in any Photoshop color space.
  PsColor? get color {
    final PsDescriptor? value = descriptor.objectValue('Clr ');
    return value == null ? null : PsColor.fromDescriptor(value);
  }
}

/// A gradient paint.
final class PsdGradientFill extends PsdFillContent {
  /// Creates a view over a gradient [descriptor].
  const PsdGradientFill({required super.descriptor});

  /// Creates a gradient paint.
  factory PsdGradientFill.create({
    required PsGradient gradient,
    PsGradientStyle style = PsGradientStyle.linear,
    double angle = 90,
    double scale = 100,
    bool reversed = false,
    bool dithered = false,
    bool aligned = true,
    double offsetX = 0,
    double offsetY = 0,
  }) => PsdGradientFill(
    descriptor: PsDescriptor(
      name: '\u0000',
      classId: 'null',
      items: [
        PsDescriptorItem(
          key: 'Grad',
          value: PsObjectValue(value: gradient.descriptor),
        ),
        PsDescriptorItem(
          key: 'Type',
          value: PsEnumeratedValue(typeId: 'GrdT', value: style.identifier),
        ),
        PsDescriptorItem(
          key: 'Angl',
          value: PsUnitFloatValue(unit: '#Ang', value: angle),
        ),
        PsDescriptorItem(
          key: 'Dthr',
          value: PsBooleanValue(value: dithered),
        ),
        PsDescriptorItem(
          key: 'Rvrs',
          value: PsBooleanValue(value: reversed),
        ),
        PsDescriptorItem(
          key: 'Algn',
          value: PsBooleanValue(value: aligned),
        ),
        PsDescriptorItem(
          key: 'Scl ',
          value: PsUnitFloatValue(unit: '#Prc', value: scale),
        ),
        PsDescriptorItem(
          key: 'Ofst',
          value: PsObjectValue(
            value: PsPoint.create(horizontal: offsetX, vertical: offsetY, unit: '#Prc').descriptor,
          ),
        ),
      ],
    ),
  );

  @override
  PsdFillKind get kind => PsdFillKind.gradient;

  /// Gradient definition.
  PsGradient? get gradient {
    final PsDescriptor? value = descriptor.objectValue('Grad');
    return value == null ? null : PsGradient.fromDescriptor(value);
  }

  /// Gradient geometry, linear when unspecified.
  PsGradientStyle get style => PsGradientStyle.fromIdentifier(descriptor.enumerationIdentifier('Type'));

  /// Angle in degrees, when stored.
  double? get angle => descriptor.scalarValue('Angl');

  /// Scale percentage, when stored.
  double? get scale => descriptor.scalarValue('Scl ');

  /// Whether the gradient direction is reversed, when stored.
  bool? get reversed => descriptor.booleanValue('Rvrs');

  /// Whether dithering is enabled, when stored.
  bool? get dithered => descriptor.booleanValue('Dthr');

  /// Whether the gradient is aligned with the layer, when stored.
  bool? get aligned => descriptor.booleanValue('Algn');

  /// Offset from the center as percentages of the layer size, when stored.
  PsPoint? get offset {
    final PsDescriptor? value = descriptor.objectValue('Ofst');
    return value == null ? null : PsPoint.fromDescriptor(value);
  }
}

/// A pattern paint.
final class PsdPatternFill extends PsdFillContent {
  /// Creates a view over a pattern [descriptor].
  const PsdPatternFill({required super.descriptor});

  /// Creates a pattern paint referring to an embedded pattern.
  factory PsdPatternFill.create({
    required PsPatternReference pattern,
    double scale = 100,
    double angle = 0,
    bool aligned = true,
    double phaseX = 0,
    double phaseY = 0,
  }) => PsdPatternFill(
    descriptor: PsDescriptor(
      name: '\u0000',
      classId: 'null',
      items: [
        PsDescriptorItem(
          key: 'Ptrn',
          value: PsObjectValue(value: pattern.descriptor),
        ),
        PsDescriptorItem(
          key: 'Scl ',
          value: PsUnitFloatValue(unit: '#Prc', value: scale),
        ),
        PsDescriptorItem(
          key: 'Angl',
          value: PsUnitFloatValue(unit: '#Ang', value: angle),
        ),
        PsDescriptorItem(
          key: 'Algn',
          value: PsBooleanValue(value: aligned),
        ),
        PsDescriptorItem(
          key: 'phase',
          value: PsObjectValue(
            value: PsPoint.create(horizontal: phaseX, vertical: phaseY).descriptor,
          ),
        ),
      ],
    ),
  );

  @override
  PsdFillKind get kind => PsdFillKind.pattern;

  /// Reference to the embedded pattern, resolved with `PsdDocument.patternFor`.
  PsPatternReference? get pattern {
    final PsDescriptor? value = descriptor.objectValue('Ptrn');
    return value == null ? null : PsPatternReference.fromDescriptor(value);
  }

  /// Scale percentage, when stored.
  double? get scale => descriptor.scalarValue('Scl ');

  /// Rotation in degrees, when stored.
  double? get angle => descriptor.scalarValue('Angl');

  /// Whether the pattern is aligned with the layer, when stored.
  bool? get aligned => descriptor.booleanValue('Algn');

  /// Pattern origin offset in pixels, when stored.
  PsPoint? get phase {
    final PsDescriptor? value = descriptor.objectValue('phase');
    return value == null ? null : PsPoint.fromDescriptor(value);
  }
}

/// Where a shape stroke sits relative to the path.
enum PsdShapeStrokeAlignment {
  /// Inside the path.
  inside('strokeStyleAlignInside'),

  /// Centered on the path.
  center('strokeStyleAlignCenter'),

  /// Outside the path.
  outside('strokeStyleAlignOutside');

  /// Photoshop `strokeStyleLineAlignment` identifier.
  final String identifier;

  /// Creates an alignment stored as [identifier].
  const PsdShapeStrokeAlignment(this.identifier);
}

/// How the open ends of a shape stroke are drawn.
enum PsdShapeStrokeCap {
  /// Flat ends at the path endpoints.
  butt('strokeStyleButtCap'),

  /// Rounded ends.
  round('strokeStyleRoundCap'),

  /// Flat ends extended by half the stroke width.
  square('strokeStyleSquareCap');

  /// Photoshop `strokeStyleLineCapType` identifier.
  final String identifier;

  /// Creates a cap stored as [identifier].
  const PsdShapeStrokeCap(this.identifier);
}

/// How the corners of a shape stroke are drawn.
enum PsdShapeStrokeJoin {
  /// Sharp corners limited by the miter limit.
  miter('strokeStyleMiterJoin'),

  /// Rounded corners.
  round('strokeStyleRoundJoin'),

  /// Cut-off corners.
  bevel('strokeStyleBevelJoin');

  /// Photoshop `strokeStyleLineJoinType` identifier.
  final String identifier;

  /// Creates a join stored as [identifier].
  const PsdShapeStrokeJoin(this.identifier);
}

/// Stroke and fill visibility of a shape layer, stored in the `vstk` block.
final class PsdShapeStroke {
  /// Complete `strokeStyle` descriptor, including properties not modeled here.
  final PsDescriptor descriptor;

  /// Creates a view over a `strokeStyle` [descriptor].
  const PsdShapeStroke({required this.descriptor});

  /// Creates a shape stroke painted with [content].
  factory PsdShapeStroke.create({
    required PsdFillContent content,
    bool strokeEnabled = true,
    bool fillEnabled = true,
    double width = 1,
    PsdShapeStrokeAlignment alignment = PsdShapeStrokeAlignment.center,
    PsdShapeStrokeCap cap = PsdShapeStrokeCap.butt,
    PsdShapeStrokeJoin join = PsdShapeStrokeJoin.miter,
    double miterLimit = 100,
    List<double> dashes = const [],
    double dashOffset = 0,
    String blendMode = 'Nrml',
    double opacity = 100,
    double resolution = 72,
  }) => PsdShapeStroke(
    descriptor: PsDescriptor(
      name: '\u0000',
      classId: 'strokeStyle',
      items: [
        const PsDescriptorItem(key: 'strokeStyleVersion', value: PsIntegerValue(value: 2)),
        PsDescriptorItem(
          key: 'strokeEnabled',
          value: PsBooleanValue(value: strokeEnabled),
        ),
        PsDescriptorItem(
          key: 'fillEnabled',
          value: PsBooleanValue(value: fillEnabled),
        ),
        PsDescriptorItem(
          key: 'strokeStyleLineWidth',
          value: PsUnitFloatValue(unit: '#Pxl', value: width),
        ),
        PsDescriptorItem(
          key: 'strokeStyleLineDashOffset',
          value: PsUnitFloatValue(unit: '#Pnt', value: dashOffset),
        ),
        PsDescriptorItem(
          key: 'strokeStyleMiterLimit',
          value: PsDoubleValue(value: miterLimit),
        ),
        PsDescriptorItem(
          key: 'strokeStyleLineCapType',
          value: PsEnumeratedValue(typeId: 'strokeStyleLineCapType', value: cap.identifier),
        ),
        PsDescriptorItem(
          key: 'strokeStyleLineJoinType',
          value: PsEnumeratedValue(typeId: 'strokeStyleLineJoinType', value: join.identifier),
        ),
        PsDescriptorItem(
          key: 'strokeStyleLineAlignment',
          value: PsEnumeratedValue(typeId: 'strokeStyleLineAlignment', value: alignment.identifier),
        ),
        const PsDescriptorItem(key: 'strokeStyleScaleLock', value: PsBooleanValue(value: false)),
        const PsDescriptorItem(key: 'strokeStyleStrokeAdjust', value: PsBooleanValue(value: false)),
        PsDescriptorItem(
          key: 'strokeStyleLineDashSet',
          value: PsListValue(
            values: [for (final double dash in dashes) PsUnitFloatValue(unit: '#Nne', value: dash)],
          ),
        ),
        PsDescriptorItem(
          key: 'strokeStyleBlendMode',
          value: PsEnumeratedValue(typeId: 'BlnM', value: blendMode),
        ),
        PsDescriptorItem(
          key: 'strokeStyleOpacity',
          value: PsUnitFloatValue(unit: '#Prc', value: opacity),
        ),
        PsDescriptorItem(
          key: 'strokeStyleContent',
          value: PsObjectValue(
            value: PsDescriptor(name: content.descriptor.name, classId: content.kind.layerClassId, items: content.descriptor.items),
          ),
        ),
        PsDescriptorItem(
          key: 'strokeStyleResolution',
          value: PsDoubleValue(value: resolution),
        ),
      ],
    ),
  );

  /// Decodes a `vstk` block payload, returning `null` when it is malformed.
  static PsdShapeStroke? tryDecode(Uint8List data) {
    try {
      final PsVersionedDescriptor decoded = PsVersionedDescriptorCodec.decodePrefix(data, expectedVersion: 16).value;
      return decoded.descriptor.classId == 'strokeStyle' ? PsdShapeStroke(descriptor: decoded.descriptor) : null;
    } on FormatException {
      return null;
    }
  }

  /// Whether the stroke is drawn.
  bool get strokeEnabled => descriptor.booleanValue('strokeEnabled') ?? true;

  /// Whether the shape's fill is drawn.
  bool get fillEnabled => descriptor.booleanValue('fillEnabled') ?? true;

  /// Stroke width in pixels, when stored.
  double? get width => descriptor.scalarValue('strokeStyleLineWidth');

  /// Stroke placement relative to the path, centered when unknown.
  PsdShapeStrokeAlignment get alignment => _byIdentifier(PsdShapeStrokeAlignment.values, 'strokeStyleLineAlignment', (value) => value.identifier) ?? PsdShapeStrokeAlignment.center;

  /// Open-end style, butt when unknown.
  PsdShapeStrokeCap get cap => _byIdentifier(PsdShapeStrokeCap.values, 'strokeStyleLineCapType', (value) => value.identifier) ?? PsdShapeStrokeCap.butt;

  /// Corner style, miter when unknown.
  PsdShapeStrokeJoin get join => _byIdentifier(PsdShapeStrokeJoin.values, 'strokeStyleLineJoinType', (value) => value.identifier) ?? PsdShapeStrokeJoin.miter;

  /// Miter limit, when stored.
  double? get miterLimit => descriptor.scalarValue('strokeStyleMiterLimit');

  /// Alternating dash and gap lengths in multiples of the stroke width.
  ///
  /// An empty list means a solid stroke.
  List<double> get dashes => [
    for (final PsDescriptorValue value in descriptor.listValue('strokeStyleLineDashSet') ?? const <PsDescriptorValue>[])
      if (value.asNumber() case final PsDescriptorNumber number) number.value,
  ];

  /// Dash pattern offset, when stored.
  double? get dashOffset => descriptor.scalarValue('strokeStyleLineDashOffset');

  /// Stroke blend-mode identifier, normal when unspecified.
  String get blendMode => descriptor.enumerationIdentifier('strokeStyleBlendMode') ?? 'Nrml';

  /// Stroke opacity percentage, opaque when unspecified.
  double get opacity => descriptor.scalarValue('strokeStyleOpacity') ?? 100;

  /// Paint of the stroke, when its class is recognized.
  PsdFillContent? get content {
    final PsDescriptor? value = descriptor.objectValue('strokeStyleContent');
    final PsdFillKind? kind = value == null ? null : PsdFillKind.fromLayerClassId(value.classId);
    return value == null || kind == null ? null : PsdFillContent.fromDescriptor(kind, value);
  }

  /// Encodes this stroke as a `vstk` block.
  PsdTaggedBlock toBlock() => PsdTaggedBlock(
    key: 'vstk',
    data: PsVersionedDescriptorCodec.encode(PsVersionedDescriptor(descriptor: descriptor)),
  );

  /// Returns the value of [values] whose identifier is stored under [key].
  T? _byIdentifier<T>(List<T> values, String key, String Function(T value) identifier) {
    final String? stored = descriptor.enumerationIdentifier(key);
    for (final T value in values) {
      if (identifier(value) == stored) {
        return value;
      }
    }
    return null;
  }
}
