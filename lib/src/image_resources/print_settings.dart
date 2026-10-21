part of '../image_resources.dart';

/// A Photoshop color-space code and four unsigned components.
final class PsdImageResourceColor extends PsdImageResourceData {
  /// Photoshop color-space code.
  final int colorSpace;

  /// Four raw 16-bit color components.
  final List<int> components;

  /// Creates an image-resource color.
  const PsdImageResourceColor({required this.colorSpace, required this.components});

  @override
  int get resourceId => PsdImageResourceIds.backgroundColor;
}

/// Boolean flags from Photoshop's page-setup dialog.
final class PsdPrintFlags extends PsdImageResourceData {
  /// Whether labels are printed.
  final bool labels;

  /// Whether crop marks are printed.
  final bool cropMarks;

  /// Whether color bars are printed.
  final bool colorBars;

  /// Whether registration marks are printed.
  final bool registrationMarks;

  /// Whether the image is printed as a negative.
  final bool negative;

  /// Whether the image is flipped.
  final bool flip;

  /// Whether interpolation is enabled.
  final bool interpolate;

  /// Whether a caption is printed.
  final bool caption;

  /// Optional ninth flag used by newer Photoshop versions.
  final bool? printFlags;

  /// Creates page-setup print flags.
  const PsdPrintFlags({
    this.labels = false,
    this.cropMarks = false,
    this.colorBars = false,
    this.registrationMarks = false,
    this.negative = false,
    this.flip = false,
    this.interpolate = false,
    this.caption = false,
    this.printFlags,
  });

  @override
  int get resourceId => PsdImageResourceIds.printFlags;
}

/// One plate's halftone-screen settings.
final class PsdHalftoneScreen {
  /// Screen frequency.
  final double frequency;

  /// Frequency-unit code.
  final int unit;

  /// Screen angle.
  final double angle;

  /// Dot-shape code.
  final int shape;

  /// Whether accurate screens are requested.
  final bool useAccurate;

  /// Whether printer defaults are requested.
  final bool usePrinter;

  /// Creates halftone-screen settings.
  const PsdHalftoneScreen({required this.frequency, required this.unit, required this.angle, required this.shape, this.useAccurate = false, this.usePrinter = false});
}

/// Halftone screens stored for one or more color plates.
final class PsdHalftoneScreens extends PsdImageResourceData {
  /// Resource identifier selecting grayscale, color, or duotone screens.
  @override
  final int resourceId;

  /// Ordered plate settings.
  final List<PsdHalftoneScreen> screens;

  /// Creates halftone-screen resource data.
  const PsdHalftoneScreens({required this.resourceId, required this.screens});
}

/// One plate's transfer curve.
final class PsdTransferFunction {
  /// Thirteen signed curve control points.
  final List<int> curve;

  /// Nonzero when this curve overrides the default.
  final int override;

  /// Creates a transfer function.
  const PsdTransferFunction({required this.curve, this.override = 0});
}

/// Transfer functions stored for one or more color plates.
final class PsdTransferFunctions extends PsdImageResourceData {
  /// Resource identifier selecting grayscale, color, or duotone curves.
  @override
  final int resourceId;

  /// Ordered transfer functions.
  final List<PsdTransferFunction> functions;

  /// Creates transfer-function resource data.
  const PsdTransferFunctions({required this.resourceId, required this.functions});
}

/// Page position and scale used when printing.
final class PsdPrintScale extends PsdImageResourceData {
  /// Raw print-style code.
  final int style;

  /// Horizontal page location.
  final double x;

  /// Vertical page location.
  final double y;

  /// Print scale.
  final double scale;

  /// Creates print-scale data.
  const PsdPrintScale({required this.style, required this.x, required this.y, required this.scale});

  @override
  int get resourceId => PsdImageResourceIds.printScale;

  /// Recognized print style, or `null` for an unknown code.
  PsdPrintScaleStyle? get styleType {
    for (final PsdPrintScaleStyle value in PsdPrintScaleStyle.values) {
      if (value.code == style) {
        return value;
      }
    }
    return null;
  }
}

/// Extended crop-mark and bleed print settings.
final class PsdPrintFlagsInfo extends PsdImageResourceData {
  /// Resource format version.
  final int version;

  /// Whether crop marks are centered.
  final bool centerCropMarks;

  /// Reserved byte retained for exact round-trips.
  final int reserved;

  /// Bleed-width fixed value.
  final int bleedWidth;

  /// Bleed-width unit or scale code.
  final int bleedScale;

  /// Creates extended print flags.
  const PsdPrintFlagsInfo({required this.version, required this.centerCropMarks, this.reserved = 0, required this.bleedWidth, required this.bleedScale});

  @override
  int get resourceId => PsdImageResourceIds.printFlagsInfo;
}
