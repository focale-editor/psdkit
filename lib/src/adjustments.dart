import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:psdkit/src/fill_content.dart';

/// Keys used by Photoshop fill and adjustment layers.
const Set<String> psdAdjustmentKeys = <String>{
  'SoCo',
  'GdFl',
  'PtFl',
  'brit',
  'levl',
  'curv',
  'expA',
  'vibA',
  'hue ',
  'hue2',
  'blnc',
  'blwh',
  'phfl',
  'mixr',
  'clrL',
  'nvrt',
  'post',
  'thrs',
  'grdm',
  'selc',
};

/// Identifies a Photoshop fill or adjustment-layer family.
enum PsdAdjustmentType {
  /// A solid-color fill layer.
  solidColor,

  /// A gradient fill layer.
  gradientFill,

  /// A pattern fill layer.
  patternFill,

  /// Brightness and contrast.
  brightnessContrast,

  /// Input, gamma, and output levels.
  levels,

  /// Point curves.
  curves,

  /// Exposure, offset, and gamma.
  exposure,

  /// Vibrance and saturation.
  vibrance,

  /// The Photoshop 4 hue/saturation format.
  legacyHueSaturation,

  /// Hue, saturation, and lightness ranges.
  hueSaturation,

  /// Shadows, midtones, and highlights color balance.
  colorBalance,

  /// Black-and-white conversion.
  blackAndWhite,

  /// A photographic warming or cooling filter.
  photoFilter,

  /// Per-channel mixing matrices.
  channelMixer,

  /// A color lookup table.
  colorLookup,

  /// Color inversion.
  invert,

  /// Posterization.
  posterize,

  /// Black-and-white thresholding.
  threshold,

  /// A tonal gradient map.
  gradientMap,

  /// Selective CMYK correction by color range.
  selectiveColor,
}

/// Base type for editable Photoshop fill and adjustment settings.
sealed class PsdAdjustment {
  /// Creates an adjustment base value.
  const PsdAdjustment();

  /// Four-character additional-layer-information key.
  String get blockKey;

  /// Semantic adjustment family.
  PsdAdjustmentType get type;
}

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

/// Backward-compatible name for a shared hue, saturation, and lightness triplet.
typedef PsdHueSaturationValues = PsHueSaturationValues;

/// Backward-compatible name for one shared hue/saturation color range.
typedef PsdHueSaturationRange = PsHueSaturationRange;

/// Modern hue/saturation settings stored in a `hue2` block.
final class PsdHueSaturationAdjustment extends PsHueSaturation implements PsdAdjustment {
  /// Creates modern hue/saturation settings.
  PsdHueSaturationAdjustment({
    super.version,
    super.colorize,
    super.colorization,
    super.master,
    required super.ranges,
    super.trailingData,
  });

  /// Wraps shared [settings], such as those read from an `.ahu` preset, as a layer adjustment.
  factory PsdHueSaturationAdjustment.fromSettings(PsHueSaturation settings) => PsdHueSaturationAdjustment(
    version: settings.version,
    colorize: settings.colorize,
    colorization: settings.colorization,
    master: settings.master,
    ranges: settings.ranges,
    trailingData: settings.trailingData,
  );

  @override
  String get blockKey => 'hue2';

  @override
  PsdAdjustmentType get type => PsdAdjustmentType.hueSaturation;
}

/// A cyan/red, magenta/green, and yellow/blue correction triplet.
final class PsdColorBalanceValues {
  /// Cyan-to-red correction.
  final int cyanRed;

  /// Magenta-to-green correction.
  final int magentaGreen;

  /// Yellow-to-blue correction.
  final int yellowBlue;

  /// Creates a color-balance correction triplet.
  const PsdColorBalanceValues({this.cyanRed = 0, this.magentaGreen = 0, this.yellowBlue = 0});
}

/// Color-balance settings stored in a `blnc` block.
final class PsdColorBalanceAdjustment extends PsdAdjustment {
  /// Shadows correction.
  final PsdColorBalanceValues shadows;

  /// Midtones correction.
  final PsdColorBalanceValues midtones;

  /// Highlights correction.
  final PsdColorBalanceValues highlights;

  /// Whether luminosity is preserved.
  final bool preserveLuminosity;

  /// Uninterpreted bytes following the documented fields.
  final Uint8List trailingData;

  /// Creates color-balance settings.
  PsdColorBalanceAdjustment({
    this.shadows = const PsdColorBalanceValues(),
    this.midtones = const PsdColorBalanceValues(),
    this.highlights = const PsdColorBalanceValues(),
    this.preserveLuminosity = true,
    Uint8List? trailingData,
  }) : trailingData = trailingData ?? Uint8List(1);

  @override
  String get blockKey => 'blnc';

  @override
  PsdAdjustmentType get type => PsdAdjustmentType.colorBalance;
}

/// Backward-compatible name for one shared channel-mixer output row.
typedef PsdChannelMixerOutput = PsChannelMixerOutput;

/// Channel-mixer settings stored in a `mixr` block.
final class PsdChannelMixerAdjustment extends PsChannelMixer implements PsdAdjustment {
  /// Creates channel-mixer settings.
  PsdChannelMixerAdjustment({
    super.version,
    super.monochrome,
    required super.outputs,
    super.trailingData,
  });

  /// Wraps shared [settings], such as those read from a `.cha` preset, as a layer adjustment.
  factory PsdChannelMixerAdjustment.fromSettings(PsChannelMixer settings) => PsdChannelMixerAdjustment(
    version: settings.version,
    monochrome: settings.monochrome,
    outputs: settings.outputs,
    trailingData: settings.trailingData,
  );

  @override
  String get blockKey => 'mixr';

  @override
  PsdAdjustmentType get type => PsdAdjustmentType.channelMixer;
}

/// Photo-filter settings retaining either the version-2 or version-3 color.
final class PsdPhotoFilterAdjustment extends PsdAdjustment {
  /// Format version, normally 2 or 3.
  final int version;

  /// Version-dependent 10-byte native or 12-byte XYZ color data.
  final Uint8List colorData;

  /// Filter density.
  final int density;

  /// Whether luminosity is preserved.
  final bool preserveLuminosity;

  /// Uninterpreted bytes following the documented fields.
  final Uint8List trailingData;

  /// Creates photo-filter settings.
  PsdPhotoFilterAdjustment({
    this.version = 3,
    required this.colorData,
    this.density = 25,
    this.preserveLuminosity = true,
    Uint8List? trailingData,
  }) : trailingData = trailingData ?? Uint8List(0);

  @override
  String get blockKey => 'phfl';

  @override
  PsdAdjustmentType get type => PsdAdjustmentType.photoFilter;
}

/// Backward-compatible name for one shared selective-color correction.
typedef PsdSelectiveColorCorrection = PsSelectiveColorCorrection;

/// Selective-color settings stored in a `selc` block.
final class PsdSelectiveColorAdjustment extends PsSelectiveColor implements PsdAdjustment {
  /// Creates selective-color settings.
  PsdSelectiveColorAdjustment({
    super.version,
    super.absolute,
    required super.corrections,
    super.trailingData,
  });

  /// Wraps shared [settings], such as those read from an `.asv` preset, as a layer adjustment.
  factory PsdSelectiveColorAdjustment.fromSettings(PsSelectiveColor settings) => PsdSelectiveColorAdjustment(
    version: settings.version,
    absolute: settings.absolute,
    corrections: settings.corrections,
    trailingData: settings.trailingData,
  );

  @override
  String get blockKey => 'selc';

  @override
  PsdAdjustmentType get type => PsdAdjustmentType.selectiveColor;
}

/// One colour stop of a gradient map, in Photoshop's legacy colour layout.
final class PsdGradientMapColorStop {
  /// Position along the gradient, from 0 to the map's [PsdGradientMapAdjustment.smoothness] scale, normally 4096.
  final int location;

  /// Transition midpoint in percent.
  final int midpoint;

  /// Colour-space identifier of [components], as in Photoshop colour structures: 0 is RGB.
  final int colorSpace;

  /// Four 16-bit colour components.
  final List<int> components;

  /// Stop kind: 0 for a user colour, 1 for the foreground, 2 for the background colour.
  final int kind;

  /// Creates a colour stop.
  PsdGradientMapColorStop({
    required this.location,
    this.midpoint = 50,
    this.colorSpace = 0,
    required List<int> components,
    this.kind = 0,
  }) : components = List<int>.unmodifiable(components);

  /// Creates a user stop from 8-bit RGB components.
  factory PsdGradientMapColorStop.rgb({required int location, required int red, required int green, required int blue, int midpoint = 50}) =>
      PsdGradientMapColorStop(location: location, midpoint: midpoint, components: [red * 257, green * 257, blue * 257, 0]);
}

/// One opacity stop of a gradient map.
final class PsdGradientMapOpacityStop {
  /// Position along the gradient, on the same scale as colour stops.
  final int location;

  /// Transition midpoint in percent.
  final int midpoint;

  /// Opacity from 0 to 255.
  final int opacity;

  /// Creates an opacity stop.
  const PsdGradientMapOpacityStop({required this.location, this.midpoint = 50, this.opacity = 255});
}

/// Gradient-map settings stored in a `grdm` block.
///
/// The colour and opacity stops use the record layout of legacy `.grd`
/// libraries. Noise parameters are always present, even for a solid gradient.
final class PsdGradientMapAdjustment extends PsdAdjustment {
  /// Format version: 1, or 3 when [method] is stored.
  final int version;

  /// Whether the gradient is reversed.
  final bool reverse;

  /// Whether the result is dithered.
  final bool dither;

  /// Interpolation method signature, such as `Gcsp`, stored by version 3.
  final String? method;

  /// Gradient name.
  final String name;

  /// Colour stops in source order.
  final List<PsdGradientMapColorStop> colorStops;

  /// Opacity stops in source order.
  final List<PsdGradientMapOpacityStop> opacityStops;

  /// Smoothness, and the scale of stop locations, normally 4096.
  final int smoothness;

  /// Whether the gradient is generated from noise instead of its stops.
  final bool noise;

  /// Noise random seed.
  final int randomSeed;

  /// Whether noise adds transparency.
  final bool showsTransparency;

  /// Whether noise restricts colours to printable values.
  final bool restrictsColors;

  /// Noise roughness from 0 to 4096.
  final int roughness;

  /// Noise colour model: 0 RGB, 1 HSB, or 2 Lab, as Photoshop numbers them.
  final int colorModel;

  /// Four noise minimum channel values.
  final List<int> minimumValues;

  /// Four noise maximum channel values.
  final List<int> maximumValues;

  /// Uninterpreted bytes following the documented fields.
  final Uint8List trailingData;

  /// Creates gradient-map settings.
  PsdGradientMapAdjustment({
    this.version = 1,
    this.reverse = false,
    this.dither = false,
    this.method,
    this.name = '',
    required List<PsdGradientMapColorStop> colorStops,
    List<PsdGradientMapOpacityStop> opacityStops = const [PsdGradientMapOpacityStop(location: 0), PsdGradientMapOpacityStop(location: 4096)],
    this.smoothness = 4096,
    this.noise = false,
    this.randomSeed = 0,
    this.showsTransparency = false,
    this.restrictsColors = false,
    this.roughness = 2048,
    this.colorModel = 3,
    List<int> minimumValues = const [0, 0, 0, 0],
    List<int> maximumValues = const [0x8000, 0x8000, 0x8000, 0x8000],
    Uint8List? trailingData,
  }) : colorStops = List<PsdGradientMapColorStop>.unmodifiable(colorStops),
       opacityStops = List<PsdGradientMapOpacityStop>.unmodifiable(opacityStops),
       minimumValues = List<int>.unmodifiable(minimumValues),
       maximumValues = List<int>.unmodifiable(maximumValues),
       trailingData = trailingData ?? Uint8List(2);

  @override
  String get blockKey => 'grdm';

  @override
  PsdAdjustmentType get type => PsdAdjustmentType.gradientMap;
}

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

/// Encodes and decodes Photoshop fill and adjustment-layer blocks.
abstract final class PsdAdjustmentCodec {
  /// Decodes one adjustment [data] selected by its tagged-block [key].
  static PsdAdjustment decode(Uint8List data, {required String key}) {
    if (!psdAdjustmentKeys.contains(key)) {
      throw PsFormatException(message: 'Unsupported adjustment key "$key"', source: data, offset: 0);
    }
    try {
      final PsBinaryReader reader = PsBinaryReader(bytes: data);
      return switch (key) {
        'brit' => _readBrightnessContrast(reader),
        'levl' => PsdLevelsAdjustment.fromSettings(PsAdjustmentSettingsCodec.readLevels(reader)),
        'curv' => _readCurves(reader),
        'expA' => _readExposure(reader),
        'hue2' => PsdHueSaturationAdjustment.fromSettings(PsAdjustmentSettingsCodec.readHueSaturation(reader)),
        'blnc' => _readColorBalance(reader),
        'phfl' => _readPhotoFilter(reader),
        'mixr' => PsdChannelMixerAdjustment.fromSettings(PsAdjustmentSettingsCodec.readChannelMixer(reader)),
        'nvrt' => PsdInvertAdjustment(data: reader.readBytes(reader.remaining)),
        'post' || 'thrs' => _readSingleValue(reader, key),
        'grdm' => _readGradientMap(reader),
        'selc' => PsdSelectiveColorAdjustment.fromSettings(PsAdjustmentSettingsCodec.readSelectiveColor(reader)),
        'SoCo' || 'GdFl' || 'PtFl' || 'vibA' || 'blwh' || 'clrL' => _readDescriptorAdjustment(reader, key),
        _ => PsdRawAdjustment(blockKey: key, type: _typeForKey(key), data: data),
      };
    } on FormatException {
      return PsdRawAdjustment(blockKey: key, type: _typeForKey(key), data: data);
    }
  }

  /// Attempts to decode an adjustment and returns `null` for malformed data.
  static PsdAdjustment? tryDecode(Uint8List data, {required String key}) {
    try {
      return decode(data, key: key);
    } on Object {
      return null;
    }
  }

  /// Encodes one semantic [adjustment] payload.
  static Uint8List encode(PsdAdjustment adjustment) {
    final PsBinaryWriter writer = PsBinaryWriter();
    switch (adjustment) {
      case PsdBrightnessContrastAdjustment():
        writer
          ..writeInt16(adjustment.brightness)
          ..writeInt16(adjustment.contrast)
          ..writeInt16(adjustment.mean)
          ..writeUint8(adjustment.labColorOnly ? 1 : 0)
          ..writeBytes(adjustment.trailingData);
      case PsdLevelsAdjustment():
        PsAdjustmentSettingsCodec.writeLevels(writer, adjustment);
      case PsdCurvesAdjustment():
        _writeCurves(writer, adjustment);
      case PsdExposureAdjustment():
        writer
          ..writeUint16(adjustment.version)
          ..writeFloat32(adjustment.exposure)
          ..writeFloat32(adjustment.offset)
          ..writeFloat32(adjustment.gamma)
          ..writeBytes(adjustment.trailingData);
      case PsdHueSaturationAdjustment():
        PsAdjustmentSettingsCodec.writeHueSaturation(writer, adjustment);
      case PsdColorBalanceAdjustment():
        _writeColorBalance(writer, adjustment);
      case PsdChannelMixerAdjustment():
        PsAdjustmentSettingsCodec.writeChannelMixer(writer, adjustment);
      case PsdPhotoFilterAdjustment():
        _writePhotoFilter(writer, adjustment);
      case PsdGradientMapAdjustment():
        _writeGradientMap(writer, adjustment);
      case PsdSelectiveColorAdjustment():
        PsAdjustmentSettingsCodec.writeSelectiveColor(writer, adjustment);
      case PsdSingleValueAdjustment():
        writer
          ..writeUint16(adjustment.value)
          ..writeBytes(adjustment.trailingData);
      case PsdInvertAdjustment():
        writer.writeBytes(adjustment.data);
      case PsdDescriptorAdjustment():
        _writeDescriptorAdjustment(writer, adjustment);
      case PsdRawAdjustment():
        writer.writeBytes(adjustment.data);
    }
    return writer.takeBytes();
  }
}

/// Reads a brightness/contrast payload, which on its own describes the legacy algorithm.
PsdBrightnessContrastAdjustment _readBrightnessContrast(PsBinaryReader reader) => PsdBrightnessContrastAdjustment(
  brightness: reader.readInt16(),
  contrast: reader.readInt16(),
  mean: reader.readInt16(),
  labColorOnly: reader.readUint8() != 0,
  useLegacy: true,
  trailingData: reader.readBytes(reader.remaining),
);

/// Reads main bitmap curves and optional version-4 duplicates.
PsdCurvesAdjustment _readCurves(PsBinaryReader reader) {
  if (reader.readUint8() != 0) {
    throw PsFormatException(message: 'Curves reserved byte must be zero', source: reader.bytes, offset: 0);
  }
  final int version = reader.readUint16();
  reader.readUint16();
  final int mask = reader.readUint16();
  final List<PsdCurve> curves = <PsdCurve>[];
  for (int channel = 0; channel < 16; channel++) {
    if (mask & (1 << channel) != 0) {
      curves.add(_readCurve(reader, channel));
    }
  }
  final List<PsdCurve> extended = <PsdCurve>[];
  if (reader.remaining >= 10 && _peekString(reader, 4) == 'Crv ') {
    reader.skip(4);
    reader.readUint16();
    final int count = reader.readUint32();
    for (int index = 0; index < count; index++) {
      extended.add(_readCurve(reader, reader.readUint16()));
    }
  }
  return PsdCurvesAdjustment(
    version: version,
    curves: curves,
    extendedCurves: extended,
    trailingData: reader.readBytes(reader.remaining),
  );
}

/// Reads one curve after its channel index has been determined.
PsdCurve _readCurve(PsBinaryReader reader, int channel) {
  final PsToneCurve curve = PsToneCurveCodec.read(reader);
  return PsdCurve(
    channel: channel,
    points: curve.points,
  );
}

/// Reads exposure floating-point values.
PsdExposureAdjustment _readExposure(PsBinaryReader reader) => PsdExposureAdjustment(
  version: reader.readUint16(),
  exposure: reader.readFloat32(),
  offset: reader.readFloat32(),
  gamma: reader.readFloat32(),
  trailingData: reader.readBytes(reader.remaining),
);

/// Reads the three tonal ranges of a color-balance adjustment.
PsdColorBalanceAdjustment _readColorBalance(PsBinaryReader reader) => PsdColorBalanceAdjustment(
  shadows: _readColorBalanceValues(reader),
  midtones: _readColorBalanceValues(reader),
  highlights: _readColorBalanceValues(reader),
  preserveLuminosity: reader.readUint8() != 0,
  trailingData: reader.readBytes(reader.remaining),
);

/// Reads one color-balance correction triplet.
PsdColorBalanceValues _readColorBalanceValues(PsBinaryReader reader) => PsdColorBalanceValues(
  cyanRed: reader.readInt16(),
  magentaGreen: reader.readInt16(),
  yellowBlue: reader.readInt16(),
);

/// Reads version-dependent photo-filter color data.
PsdPhotoFilterAdjustment _readPhotoFilter(PsBinaryReader reader) {
  final int version = reader.readUint16();
  final int colorLength = version == 3 ? 12 : 10;
  return PsdPhotoFilterAdjustment(
    version: version,
    colorData: reader.readBytes(colorLength),
    density: reader.readUint32(),
    preserveLuminosity: reader.readUint8() != 0,
    trailingData: reader.readBytes(reader.remaining),
  );
}

/// Reads posterize or threshold data.
PsdSingleValueAdjustment _readSingleValue(PsBinaryReader reader, String key) => PsdSingleValueAdjustment(
  type: key == 'post' ? PsdAdjustmentType.posterize : PsdAdjustmentType.threshold,
  value: reader.readUint16(),
  trailingData: reader.readBytes(reader.remaining),
);

/// Reads gradient-map settings, rejecting layouts other than the documented one.
PsdGradientMapAdjustment _readGradientMap(PsBinaryReader reader) {
  final int version = reader.readUint16();
  if (version != 1 && version != 3) {
    throw PsFormatException(message: 'Unsupported gradient map version $version', source: reader.bytes, offset: 0);
  }
  final bool reverse = reader.readUint8() != 0;
  final bool dither = reader.readUint8() != 0;
  final String? method = version == 3 ? reader.readString(4) : null;
  final int nameLength = reader.readUint32();
  if (nameLength > reader.remaining ~/ 2) {
    throw PsFormatException(message: 'Gradient map name length $nameLength exceeds the block', source: reader.bytes, offset: reader.offset - 4);
  }
  final List<int> name = [for (int index = 0; index < nameLength; index++) reader.readUint16()];
  if (name.isNotEmpty && name.last == 0) {
    name.removeLast();
  }
  final List<PsdGradientMapColorStop> colorStops = [
    for (int index = reader.readUint16(); index > 0; index--)
      PsdGradientMapColorStop(
        location: reader.readUint32(),
        midpoint: reader.readUint32(),
        colorSpace: reader.readUint16(),
        components: [for (int component = 0; component < 4; component++) reader.readUint16()],
        kind: reader.readUint16(),
      ),
  ];
  final List<PsdGradientMapOpacityStop> opacityStops = [
    for (int index = reader.readUint16(); index > 0; index--) PsdGradientMapOpacityStop(location: reader.readUint32(), midpoint: reader.readUint32(), opacity: reader.readUint16()),
  ];
  final int expansionCount = reader.readUint16();
  final int smoothness = reader.readUint16();
  final int expansionLength = reader.readUint16();
  if (expansionCount != 2 || expansionLength != 32) {
    throw PsFormatException(message: 'Unsupported gradient map expansion $expansionCount/$expansionLength', source: reader.bytes, offset: reader.offset);
  }
  return PsdGradientMapAdjustment(
    version: version,
    reverse: reverse,
    dither: dither,
    method: method,
    name: String.fromCharCodes(name),
    colorStops: colorStops,
    opacityStops: opacityStops,
    smoothness: smoothness,
    noise: reader.readUint16() != 0,
    randomSeed: reader.readUint32(),
    showsTransparency: reader.readUint16() != 0,
    restrictsColors: reader.readUint16() != 0,
    roughness: reader.readUint32(),
    colorModel: reader.readUint16(),
    minimumValues: [for (int index = 0; index < 4; index++) reader.readUint16()],
    maximumValues: [for (int index = 0; index < 4; index++) reader.readUint16()],
    trailingData: reader.readBytes(reader.remaining),
  );
}

/// Writes gradient-map settings.
void _writeGradientMap(PsBinaryWriter writer, PsdGradientMapAdjustment adjustment) {
  final String? method = adjustment.method;
  if ((adjustment.version == 3) != (method != null) || method != null && method.length != 4) {
    throw const PsWriteException(message: 'A version 3 gradient map needs a four-character method, and only version 3 stores one');
  }
  if (adjustment.colorStops.any((stop) => stop.components.length != 4) || adjustment.minimumValues.length != 4 || adjustment.maximumValues.length != 4) {
    throw const PsWriteException(message: 'Gradient map colours and noise ranges need four components');
  }
  writer
    ..writeUint16(adjustment.version)
    ..writeUint8(adjustment.reverse ? 1 : 0)
    ..writeUint8(adjustment.dither ? 1 : 0);
  if (method != null) {
    writer.writeString(method);
  }
  writer
    ..writeUint32(adjustment.name.length + 1)
    ..writeUint16List([...adjustment.name.codeUnits, 0])
    ..writeUint16(adjustment.colorStops.length);
  for (final PsdGradientMapColorStop stop in adjustment.colorStops) {
    writer
      ..writeUint32(stop.location)
      ..writeUint32(stop.midpoint)
      ..writeUint16(stop.colorSpace)
      ..writeUint16List(stop.components)
      ..writeUint16(stop.kind);
  }
  writer.writeUint16(adjustment.opacityStops.length);
  for (final PsdGradientMapOpacityStop stop in adjustment.opacityStops) {
    writer
      ..writeUint32(stop.location)
      ..writeUint32(stop.midpoint)
      ..writeUint16(stop.opacity);
  }
  writer
    ..writeUint16(2)
    ..writeUint16(adjustment.smoothness)
    ..writeUint16(32)
    ..writeUint16(adjustment.noise ? 1 : 0)
    ..writeUint32(adjustment.randomSeed)
    ..writeUint16(adjustment.showsTransparency ? 1 : 0)
    ..writeUint16(adjustment.restrictsColors ? 1 : 0)
    ..writeUint32(adjustment.roughness)
    ..writeUint16(adjustment.colorModel)
    ..writeUint16List(adjustment.minimumValues)
    ..writeUint16List(adjustment.maximumValues)
    ..writeBytes(adjustment.trailingData);
}

/// Reads a descriptor-backed fill or adjustment.
PsdDescriptorAdjustment _readDescriptorAdjustment(PsBinaryReader reader, String key) {
  int? version;
  if (key == 'clrL') {
    version = reader.readUint16();
  }
  final int descriptorVersion = reader.readUint32();
  final Uint8List payload = reader.readBytes(reader.remaining);
  final ({PsDescriptor descriptor, int bytesRead}) decoded = PsDescriptorCodec.decodePrefix(payload);
  return PsdDescriptorAdjustment(
    blockKey: key,
    type: _typeForKey(key),
    version: version,
    descriptorVersion: descriptorVersion,
    descriptor: decoded.descriptor,
    trailingData: Uint8List.fromList(Uint8List.sublistView(payload, decoded.bytesRead)),
  );
}

/// Writes bitmap curves and optional extended curves.
void _writeCurves(PsBinaryWriter writer, PsdCurvesAdjustment adjustment) {
  int mask = 0;
  for (final PsdCurve curve in adjustment.curves) {
    if (curve.channel < 0 || curve.channel > 15) {
      throw PsWriteException(message: 'Main curve channel ${curve.channel} must be from 0 through 15');
    }
    mask |= 1 << curve.channel;
  }
  writer
    ..writeUint8(0)
    ..writeUint16(adjustment.version)
    ..writeUint16(0)
    ..writeUint16(mask);
  final List<PsdCurve> ordered = <PsdCurve>[...adjustment.curves]..sort((left, right) => left.channel.compareTo(right.channel));
  for (final PsdCurve curve in ordered) {
    _writeCurve(writer, curve);
  }
  if (adjustment.extendedCurves.isNotEmpty) {
    writer
      ..writeString('Crv ')
      ..writeUint16(4)
      ..writeUint32(adjustment.extendedCurves.length);
    for (final PsdCurve curve in adjustment.extendedCurves) {
      writer.writeUint16(curve.channel);
      _writeCurve(writer, curve);
    }
  }
  writer.writeBytes(adjustment.trailingData);
}

/// Writes one curve without a channel prefix.
void _writeCurve(PsBinaryWriter writer, PsdCurve curve) {
  PsToneCurveCodec.write(writer, PsToneCurve(points: curve.points));
}

/// Writes the color-balance tonal ranges.
void _writeColorBalance(PsBinaryWriter writer, PsdColorBalanceAdjustment adjustment) {
  _writeColorBalanceValues(writer, adjustment.shadows);
  _writeColorBalanceValues(writer, adjustment.midtones);
  _writeColorBalanceValues(writer, adjustment.highlights);
  writer
    ..writeUint8(adjustment.preserveLuminosity ? 1 : 0)
    ..writeBytes(adjustment.trailingData);
}

/// Writes one color-balance correction triplet.
void _writeColorBalanceValues(PsBinaryWriter writer, PsdColorBalanceValues values) {
  writer
    ..writeInt16(values.cyanRed)
    ..writeInt16(values.magentaGreen)
    ..writeInt16(values.yellowBlue);
}

/// Writes version-dependent photo-filter data.
void _writePhotoFilter(PsBinaryWriter writer, PsdPhotoFilterAdjustment adjustment) {
  final int expectedLength = adjustment.version == 3 ? 12 : 10;
  if (adjustment.colorData.length != expectedLength) {
    throw PsWriteException(message: 'Photo filter version ${adjustment.version} requires $expectedLength color bytes');
  }
  writer
    ..writeUint16(adjustment.version)
    ..writeBytes(adjustment.colorData)
    ..writeUint32(adjustment.density)
    ..writeUint8(adjustment.preserveLuminosity ? 1 : 0)
    ..writeBytes(adjustment.trailingData);
}

/// Writes the version header and complete action descriptor.
void _writeDescriptorAdjustment(PsBinaryWriter writer, PsdDescriptorAdjustment adjustment) {
  if (adjustment.blockKey == 'clrL') {
    writer.writeUint16(adjustment.version ?? 1);
  }
  writer
    ..writeUint32(adjustment.descriptorVersion)
    ..writeBytes(PsDescriptorCodec.encode(adjustment.descriptor))
    ..writeBytes(adjustment.trailingData);
}

/// Peeks at [length] one-byte characters without advancing [reader].
String _peekString(PsBinaryReader reader, int length) => String.fromCharCodes(
  Uint8List.sublistView(reader.bytes, reader.offset, reader.offset + length),
);

/// Maps a tagged-block [key] to its semantic adjustment family.
PsdAdjustmentType _typeForKey(String key) => switch (key) {
  'SoCo' => PsdAdjustmentType.solidColor,
  'GdFl' => PsdAdjustmentType.gradientFill,
  'PtFl' => PsdAdjustmentType.patternFill,
  'brit' => PsdAdjustmentType.brightnessContrast,
  'levl' => PsdAdjustmentType.levels,
  'curv' => PsdAdjustmentType.curves,
  'expA' => PsdAdjustmentType.exposure,
  'vibA' => PsdAdjustmentType.vibrance,
  'hue ' => PsdAdjustmentType.legacyHueSaturation,
  'hue2' => PsdAdjustmentType.hueSaturation,
  'blnc' => PsdAdjustmentType.colorBalance,
  'blwh' => PsdAdjustmentType.blackAndWhite,
  'phfl' => PsdAdjustmentType.photoFilter,
  'mixr' => PsdAdjustmentType.channelMixer,
  'clrL' => PsdAdjustmentType.colorLookup,
  'nvrt' => PsdAdjustmentType.invert,
  'post' => PsdAdjustmentType.posterize,
  'thrs' => PsdAdjustmentType.threshold,
  'grdm' => PsdAdjustmentType.gradientMap,
  'selc' => PsdAdjustmentType.selectiveColor,
  _ => throw ArgumentError.value(key, 'key', 'is not an adjustment key'),
};
