part of '../fill_content.dart';

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
