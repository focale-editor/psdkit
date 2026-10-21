part of '../adjustments.dart';

/// Brightness/contrast values stored in a `brit` block.
final class PsdBrightnessContrastAdjustment extends PsdAdjustment {
  /// Brightness value.
  final int brightness;

  /// Contrast value.
  final int contrast;

  /// Historical mean value used by the adjustment.
  final int mean;

  /// Whether the adjustment applies only to Lab color.
  final bool labColorOnly;

  /// Whether Photoshop's pre-CS3 algorithm applies.
  ///
  /// Modern Photoshop keeps `brit` for older readers and stores its current
  /// settings in a `CgEd` descriptor; [PsdLayer.adjustment] reads them from
  /// there, and [PsdLayer.withAdjustment] writes both. A `brit` payload decoded
  /// on its own is legacy.
  final bool useLegacy;

  /// Whether the values came from Photoshop's Auto button.
  final bool automatic;

  /// Uninterpreted bytes following the documented fields.
  final Uint8List trailingData;

  /// Creates brightness/contrast settings, using the modern algorithm by default.
  PsdBrightnessContrastAdjustment({
    this.brightness = 0,
    this.contrast = 0,
    this.mean = 127,
    this.labColorOnly = false,
    this.useLegacy = false,
    this.automatic = false,
    Uint8List? trailingData,
  }) : trailingData = trailingData ?? Uint8List(1);

  /// Reads the modern settings Photoshop stores in a `CgEd` [descriptor], or returns `null` when it describes another adjustment.
  static PsdBrightnessContrastAdjustment? fromContentGeneratorDescriptor(PsDescriptor descriptor, {Uint8List? trailingData}) {
    final int? brightness = descriptor.integerValue('Brgh', mode: .compatible);
    final int? contrast = descriptor.integerValue('Cntr', mode: .compatible);
    if (brightness == null || contrast == null) {
      return null;
    }
    return PsdBrightnessContrastAdjustment(
      brightness: brightness,
      contrast: contrast,
      mean: descriptor.integerValue('means', mode: .compatible) ?? 127,
      labColorOnly: descriptor.booleanValue('Lab ', mode: .compatible) ?? false,
      useLegacy: descriptor.booleanValue('useLegacy', mode: .compatible) ?? false,
      automatic: descriptor.booleanValue('Auto', mode: .compatible) ?? false,
      trailingData: trailingData,
    );
  }

  /// The `CgEd` descriptor Photoshop writes for these settings.
  PsDescriptor toContentGeneratorDescriptor() => PsDescriptor(
    name: '',
    classId: 'null',
    items: [
      const PsDescriptorItem(key: 'Vrsn', value: PsIntegerValue(value: 1)),
      PsDescriptorItem(
        key: 'Brgh',
        value: PsIntegerValue(value: brightness),
      ),
      PsDescriptorItem(
        key: 'Cntr',
        value: PsIntegerValue(value: contrast),
      ),
      PsDescriptorItem(
        key: 'means',
        value: PsIntegerValue(value: mean),
      ),
      PsDescriptorItem(
        key: 'Lab ',
        value: PsBooleanValue(value: labColorOnly),
      ),
      PsDescriptorItem(
        key: 'useLegacy',
        value: PsBooleanValue(value: useLegacy),
      ),
      PsDescriptorItem(
        key: 'Auto',
        value: PsBooleanValue(value: automatic),
      ),
    ],
  );

  @override
  String get blockKey => 'brit';

  @override
  PsdAdjustmentType get type => PsdAdjustmentType.brightnessContrast;
}

/// Backward-compatible name for one shared levels channel record.
typedef PsdLevelRecord = PsLevelRecord;

/// The fixed and extended channel records stored in a `levl` block.
final class PsdLevelsAdjustment extends PsLevels implements PsdAdjustment {
  /// Creates levels settings.
  PsdLevelsAdjustment({
    super.version,
    required super.records,
    super.extendedRecords,
    super.extendedVersion,
    super.trailingData,
  });

  /// Creates the 29 neutral levels records expected by Photoshop.
  factory PsdLevelsAdjustment.identity() => PsdLevelsAdjustment.fromSettings(PsLevels.identity());

  /// Wraps shared [settings], such as those read from an `.alv` preset, as a layer adjustment.
  factory PsdLevelsAdjustment.fromSettings(PsLevels settings) => PsdLevelsAdjustment(
    version: settings.version,
    records: settings.records,
    extendedRecords: settings.extendedRecords,
    extendedVersion: settings.extendedVersion,
    trailingData: settings.trailingData,
  );

  @override
  String get blockKey => 'levl';

  @override
  PsdAdjustmentType get type => PsdAdjustmentType.levels;
}

/// Backward-compatible name for a shared Photoshop tone-curve point.
typedef PsdCurvePoint = PsToneCurvePoint;

/// A point curve associated with one Photoshop channel index.
final class PsdCurve {
  /// Zero-based Photoshop curve channel index.
  final int channel;

  /// Ordered control points.
  final List<PsdCurvePoint> points;

  /// Creates one channel curve.
  const PsdCurve({required this.channel, required this.points});

  /// Creates a two-point identity curve for [channel].
  const PsdCurve.identity({this.channel = 0})
    : points = const <PsdCurvePoint>[
        PsdCurvePoint(input: 0, output: 0),
        PsdCurvePoint(input: 255, output: 255),
      ];

  /// Whether every point maps its input to the same output.
  bool get isIdentity => _toneCurve.isIdentity;

  /// Whether point inputs are strictly increasing in source order.
  bool get hasStrictlyIncreasingInputs => _toneCurve.hasStrictlyIncreasingInputs;

  /// Evaluates one raw 0 through 255 input coordinate.
  double evaluate(
    double input, {
    PsToneCurveInterpolation interpolation = PsToneCurveInterpolation.naturalCubic,
    bool clampOutput = true,
  }) => _toneCurve.evaluate(
    input,
    interpolation: interpolation,
    clampOutput: clampOutput,
  );

  /// Evaluates an input normalized to the 0 through 1 range.
  double evaluateNormalized(
    double input, {
    PsToneCurveInterpolation interpolation = PsToneCurveInterpolation.naturalCubic,
    bool clampOutput = true,
  }) => _toneCurve.evaluateNormalized(
    input,
    interpolation: interpolation,
    clampOutput: clampOutput,
  );

  /// Builds an evenly sampled raw-coordinate lookup table.
  Float64List toLookupTable({
    int size = 256,
    PsToneCurveInterpolation interpolation = PsToneCurveInterpolation.naturalCubic,
    bool clampOutput = true,
  }) => _toneCurve.toLookupTable(
    size: size,
    interpolation: interpolation,
    clampOutput: clampOutput,
  );

  /// Builds an evenly sampled 8-bit lookup table.
  Uint8List toUint8LookupTable({
    int size = 256,
    PsToneCurveInterpolation interpolation = PsToneCurveInterpolation.naturalCubic,
  }) => _toneCurve.toUint8LookupTable(
    size: size,
    interpolation: interpolation,
  );

  /// Shared format-neutral semantics for these control points.
  PsToneCurve get _toneCurve => PsToneCurve(points: points);
}

/// Point curves stored in a `curv` adjustment block.
final class PsdCurvesAdjustment extends PsdAdjustment {
  /// Curves format version, normally 1.
  final int version;

  /// Curves selected by the main channel bitmap.
  final List<PsdCurve> curves;

  /// Optional version-4 curves following the `Crv ` marker.
  final List<PsdCurve> extendedCurves;

  /// Uninterpreted bytes after the main and extended curves.
  final Uint8List trailingData;

  /// Creates point-curve settings.
  PsdCurvesAdjustment({
    this.version = 1,
    required this.curves,
    this.extendedCurves = const <PsdCurve>[],
    Uint8List? trailingData,
  }) : trailingData = trailingData ?? Uint8List(0);

  /// Creates a neutral master curve.
  factory PsdCurvesAdjustment.identity() => PsdCurvesAdjustment(curves: const <PsdCurve>[PsdCurve.identity()]);

  @override
  String get blockKey => 'curv';

  @override
  PsdAdjustmentType get type => PsdAdjustmentType.curves;
}

/// Exposure values stored as 32-bit floating-point numbers.
final class PsdExposureAdjustment extends PsdAdjustment {
  /// Format version, normally 1.
  final int version;

  /// Exposure in stops.
  final double exposure;

  /// Linear offset.
  final double offset;

  /// Gamma correction.
  final double gamma;

  /// Uninterpreted bytes following the documented fields.
  final Uint8List trailingData;

  /// Creates exposure settings.
  PsdExposureAdjustment({
    this.version = 1,
    this.exposure = 0,
    this.offset = 0,
    this.gamma = 1,
    Uint8List? trailingData,
  }) : trailingData = trailingData ?? Uint8List(2);

  @override
  String get blockKey => 'expA';

  @override
  PsdAdjustmentType get type => PsdAdjustmentType.exposure;
}
