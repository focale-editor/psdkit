part of '../fill_content.dart';

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
