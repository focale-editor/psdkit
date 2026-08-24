import 'dart:typed_data';

import 'package:pscore/pscore.dart';

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

  /// Uninterpreted bytes following the documented fields.
  final Uint8List trailingData;

  /// Creates brightness/contrast settings.
  PsdBrightnessContrastAdjustment({
    this.brightness = 0,
    this.contrast = 0,
    this.mean = 127,
    this.labColorOnly = false,
    Uint8List? trailingData,
  }) : trailingData = trailingData ?? Uint8List(0);

  @override
  String get blockKey => 'brit';

  @override
  PsdAdjustmentType get type => PsdAdjustmentType.brightnessContrast;
}

/// One channel record in a levels adjustment.
final class PsdLevelRecord {
  /// Input black point.
  final int inputFloor;

  /// Input white point.
  final int inputCeiling;

  /// Output black point.
  final int outputFloor;

  /// Output white point.
  final int outputCeiling;

  /// Gamma encoded as hundredths, where 100 means 1.0.
  final int gamma;

  /// Creates one levels record.
  const PsdLevelRecord({
    this.inputFloor = 0,
    this.inputCeiling = 255,
    this.outputFloor = 0,
    this.outputCeiling = 255,
    this.gamma = 100,
  });

  /// Gamma converted to its user-facing floating-point value.
  double get gammaValue => gamma / 100;
}

/// The fixed and extended channel records stored in a `levl` block.
final class PsdLevelsAdjustment extends PsdAdjustment {
  /// Main format version, normally 2.
  final int version;

  /// The 29 standard channel records.
  final List<PsdLevelRecord> records;

  /// Optional Photoshop extended channel records.
  final List<PsdLevelRecord> extendedRecords;

  /// Extended-record format version, normally 3.
  final int extendedVersion;

  /// Uninterpreted bytes following the decoded records.
  final Uint8List trailingData;

  /// Creates levels settings.
  PsdLevelsAdjustment({
    this.version = 2,
    required this.records,
    this.extendedRecords = const <PsdLevelRecord>[],
    this.extendedVersion = 3,
    Uint8List? trailingData,
  }) : trailingData = trailingData ?? Uint8List(0);

  /// Creates the 29 neutral levels records expected by Photoshop.
  factory PsdLevelsAdjustment.identity() => PsdLevelsAdjustment(
    records: List<PsdLevelRecord>.unmodifiable(List<PsdLevelRecord>.filled(29, const PsdLevelRecord())),
  );

  @override
  String get blockKey => 'levl';

  @override
  PsdAdjustmentType get type => PsdAdjustmentType.levels;
}

/// One input/output point in a Photoshop curve.
final class PsdCurvePoint {
  /// Horizontal input value, normally from 0 through 255.
  final int input;

  /// Vertical output value, normally from 0 through 255.
  final int output;

  /// Creates a curve point.
  const PsdCurvePoint({required this.input, required this.output});
}

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

/// Exposure values stored as signed 16.16 fixed-point numbers.
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
  }) : trailingData = trailingData ?? Uint8List(0);

  @override
  String get blockKey => 'expA';

  @override
  PsdAdjustmentType get type => PsdAdjustmentType.exposure;
}

/// Three signed hue, saturation, and lightness values.
final class PsdHueSaturationValues {
  /// Hue change.
  final int hue;

  /// Saturation change.
  final int saturation;

  /// Lightness change.
  final int lightness;

  /// Creates one HSL value triplet.
  const PsdHueSaturationValues({this.hue = 0, this.saturation = 0, this.lightness = 0});
}

/// One editable color range in a hue/saturation adjustment.
final class PsdHueSaturationRange {
  /// Four range boundary values.
  final List<int> boundaries;

  /// HSL changes within the range.
  final PsdHueSaturationValues values;

  /// Creates one hue/saturation range.
  const PsdHueSaturationRange({required this.boundaries, this.values = const PsdHueSaturationValues()});
}

/// Modern hue/saturation settings stored in a `hue2` block.
final class PsdHueSaturationAdjustment extends PsdAdjustment {
  /// Format version, normally 2.
  final int version;

  /// Whether Photoshop uses the colorization controls.
  final bool colorize;

  /// Colorization values.
  final PsdHueSaturationValues colorization;

  /// Master HSL changes.
  final PsdHueSaturationValues master;

  /// Six red-through-magenta color ranges.
  final List<PsdHueSaturationRange> ranges;

  /// Uninterpreted bytes following the documented fields.
  final Uint8List trailingData;

  /// Creates modern hue/saturation settings.
  PsdHueSaturationAdjustment({
    this.version = 2,
    this.colorize = false,
    this.colorization = const PsdHueSaturationValues(),
    this.master = const PsdHueSaturationValues(),
    required this.ranges,
    Uint8List? trailingData,
  }) : trailingData = trailingData ?? Uint8List(0);

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

/// One output channel in a channel-mixer adjustment.
final class PsdChannelMixerOutput {
  /// Four source-channel percentages.
  final List<int> channels;

  /// Constant percentage added to the output.
  final int constant;

  /// Creates one channel-mixer output row.
  const PsdChannelMixerOutput({required this.channels, this.constant = 0});
}

/// Channel-mixer settings stored in a `mixr` block.
final class PsdChannelMixerAdjustment extends PsdAdjustment {
  /// Format version, normally 1.
  final int version;

  /// Whether the output is monochrome.
  final bool monochrome;

  /// Four RGB/CMYK output rows.
  final List<PsdChannelMixerOutput> outputs;

  /// Uninterpreted bytes following the documented fields.
  final Uint8List trailingData;

  /// Creates channel-mixer settings.
  PsdChannelMixerAdjustment({
    this.version = 1,
    this.monochrome = false,
    required this.outputs,
    Uint8List? trailingData,
  }) : trailingData = trailingData ?? Uint8List(0);

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

/// A cyan, magenta, yellow, and black selective-color correction.
final class PsdSelectiveColorCorrection {
  /// Cyan correction.
  final int cyan;

  /// Magenta correction.
  final int magenta;

  /// Yellow correction.
  final int yellow;

  /// Black correction.
  final int black;

  /// Creates one selective-color correction record.
  const PsdSelectiveColorCorrection({this.cyan = 0, this.magenta = 0, this.yellow = 0, this.black = 0});
}

/// Selective-color settings stored in a `selc` block.
final class PsdSelectiveColorAdjustment extends PsdAdjustment {
  /// Format version, normally 1.
  final int version;

  /// Whether corrections are absolute instead of relative.
  final bool absolute;

  /// Reserved record followed by red, yellow, green, cyan, blue, magenta,
  /// white, neutral, and black corrections.
  final List<PsdSelectiveColorCorrection> corrections;

  /// Uninterpreted bytes following the documented fields.
  final Uint8List trailingData;

  /// Creates selective-color settings.
  PsdSelectiveColorAdjustment({
    this.version = 1,
    this.absolute = false,
    required this.corrections,
    Uint8List? trailingData,
  }) : trailingData = trailingData ?? Uint8List(0);

  @override
  String get blockKey => 'selc';

  @override
  PsdAdjustmentType get type => PsdAdjustmentType.selectiveColor;
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
        'levl' => _readLevels(reader),
        'curv' => _readCurves(reader),
        'expA' => _readExposure(reader),
        'hue2' => _readHueSaturation(reader),
        'blnc' => _readColorBalance(reader),
        'phfl' => _readPhotoFilter(reader),
        'mixr' => _readChannelMixer(reader),
        'nvrt' => PsdInvertAdjustment(data: reader.readBytes(reader.remaining)),
        'post' || 'thrs' => _readSingleValue(reader, key),
        'selc' => _readSelectiveColor(reader),
        'SoCo' || 'GdFl' || 'PtFl' || 'vibA' || 'blwh' || 'clrL' => _readDescriptorAdjustment(reader, key),
        _ => PsdRawAdjustment(blockKey: key, type: _typeForKey(key), data: data),
      };
    } on PsFormatException {
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
        _writeLevels(writer, adjustment);
      case PsdCurvesAdjustment():
        _writeCurves(writer, adjustment);
      case PsdExposureAdjustment():
        writer
          ..writeUint16(adjustment.version)
          ..writeInt32(_fixed(adjustment.exposure))
          ..writeInt32(_fixed(adjustment.offset))
          ..writeInt32(_fixed(adjustment.gamma))
          ..writeBytes(adjustment.trailingData);
      case PsdHueSaturationAdjustment():
        _writeHueSaturation(writer, adjustment);
      case PsdColorBalanceAdjustment():
        _writeColorBalance(writer, adjustment);
      case PsdChannelMixerAdjustment():
        _writeChannelMixer(writer, adjustment);
      case PsdPhotoFilterAdjustment():
        _writePhotoFilter(writer, adjustment);
      case PsdSelectiveColorAdjustment():
        _writeSelectiveColor(writer, adjustment);
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

/// Reads a brightness/contrast payload.
PsdBrightnessContrastAdjustment _readBrightnessContrast(PsBinaryReader reader) => PsdBrightnessContrastAdjustment(
  brightness: reader.readInt16(),
  contrast: reader.readInt16(),
  mean: reader.readInt16(),
  labColorOnly: reader.readUint8() != 0,
  trailingData: reader.readBytes(reader.remaining),
);

/// Reads the standard and optional extended levels records.
PsdLevelsAdjustment _readLevels(PsBinaryReader reader) {
  final int version = reader.readUint16();
  final List<PsdLevelRecord> records = <PsdLevelRecord>[for (int index = 0; index < 29; index++) _readLevelRecord(reader)];
  final List<PsdLevelRecord> extended = <PsdLevelRecord>[];
  int extendedVersion = 3;
  if (reader.remaining >= 8 && _peekString(reader, 4) == 'Lvls') {
    reader.skip(4);
    extendedVersion = reader.readUint16();
    final int count = reader.readUint16();
    for (int index = 29; index < count; index++) {
      extended.add(_readLevelRecord(reader));
    }
  }
  return PsdLevelsAdjustment(
    version: version,
    records: records,
    extendedRecords: extended,
    extendedVersion: extendedVersion,
    trailingData: reader.readBytes(reader.remaining),
  );
}

/// Reads one levels channel record.
PsdLevelRecord _readLevelRecord(PsBinaryReader reader) => PsdLevelRecord(
  inputFloor: reader.readUint16(),
  inputCeiling: reader.readUint16(),
  outputFloor: reader.readUint16(),
  outputCeiling: reader.readUint16(),
  gamma: reader.readUint16(),
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
  final int count = reader.readUint16();
  return PsdCurve(
    channel: channel,
    points: <PsdCurvePoint>[
      for (int index = 0; index < count; index++) PsdCurvePoint(output: reader.readUint16(), input: reader.readUint16()),
    ],
  );
}

/// Reads exposure fixed-point values.
PsdExposureAdjustment _readExposure(PsBinaryReader reader) => PsdExposureAdjustment(
  version: reader.readUint16(),
  exposure: reader.readInt32() / 65536,
  offset: reader.readInt32() / 65536,
  gamma: reader.readInt32() / 65536,
  trailingData: reader.readBytes(reader.remaining),
);

/// Reads modern hue/saturation settings.
PsdHueSaturationAdjustment _readHueSaturation(PsBinaryReader reader) {
  final int version = reader.readUint16();
  final bool colorize = reader.readUint8() != 0;
  reader.readUint8();
  final PsdHueSaturationValues colorization = _readHueValues(reader);
  final PsdHueSaturationValues master = _readHueValues(reader);
  final List<PsdHueSaturationRange> ranges = <PsdHueSaturationRange>[
    for (int index = 0; index < 6; index++)
      PsdHueSaturationRange(
        boundaries: <int>[for (int boundary = 0; boundary < 4; boundary++) reader.readInt16()],
        values: _readHueValues(reader),
      ),
  ];
  return PsdHueSaturationAdjustment(
    version: version,
    colorize: colorize,
    colorization: colorization,
    master: master,
    ranges: ranges,
    trailingData: reader.readBytes(reader.remaining),
  );
}

/// Reads one HSL triplet.
PsdHueSaturationValues _readHueValues(PsBinaryReader reader) => PsdHueSaturationValues(
  hue: reader.readInt16(),
  saturation: reader.readInt16(),
  lightness: reader.readInt16(),
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

/// Reads four channel-mixer output rows.
PsdChannelMixerAdjustment _readChannelMixer(PsBinaryReader reader) => PsdChannelMixerAdjustment(
  version: reader.readUint16(),
  monochrome: reader.readUint16() != 0,
  outputs: <PsdChannelMixerOutput>[
    for (int output = 0; output < 4; output++)
      PsdChannelMixerOutput(
        channels: <int>[for (int channel = 0; channel < 4; channel++) reader.readInt16()],
        constant: reader.readInt16(),
      ),
  ],
  trailingData: reader.readBytes(reader.remaining),
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

/// Reads all ten selective-color plate records.
PsdSelectiveColorAdjustment _readSelectiveColor(PsBinaryReader reader) => PsdSelectiveColorAdjustment(
  version: reader.readUint16(),
  absolute: reader.readUint16() != 0,
  corrections: <PsdSelectiveColorCorrection>[
    for (int index = 0; index < 10; index++)
      PsdSelectiveColorCorrection(
        cyan: reader.readInt16(),
        magenta: reader.readInt16(),
        yellow: reader.readInt16(),
        black: reader.readInt16(),
      ),
  ],
  trailingData: reader.readBytes(reader.remaining),
);

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

/// Writes standard and optional extended levels records.
void _writeLevels(PsBinaryWriter writer, PsdLevelsAdjustment adjustment) {
  if (adjustment.records.length != 29) {
    throw const PsWriteException(message: 'Levels adjustments require exactly 29 standard records');
  }
  writer.writeUint16(adjustment.version);
  for (final PsdLevelRecord record in adjustment.records) {
    _writeLevelRecord(writer, record);
  }
  if (adjustment.extendedRecords.isNotEmpty) {
    writer
      ..writeString('Lvls')
      ..writeUint16(adjustment.extendedVersion)
      ..writeUint16(29 + adjustment.extendedRecords.length);
    for (final PsdLevelRecord record in adjustment.extendedRecords) {
      _writeLevelRecord(writer, record);
    }
  }
  writer.writeBytes(adjustment.trailingData);
}

/// Writes one levels channel record.
void _writeLevelRecord(PsBinaryWriter writer, PsdLevelRecord record) {
  writer
    ..writeUint16(record.inputFloor)
    ..writeUint16(record.inputCeiling)
    ..writeUint16(record.outputFloor)
    ..writeUint16(record.outputCeiling)
    ..writeUint16(record.gamma);
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
  writer.writeUint16(curve.points.length);
  for (final PsdCurvePoint point in curve.points) {
    writer
      ..writeUint16(point.output)
      ..writeUint16(point.input);
  }
}

/// Writes modern hue/saturation settings.
void _writeHueSaturation(PsBinaryWriter writer, PsdHueSaturationAdjustment adjustment) {
  if (adjustment.ranges.length != 6) {
    throw const PsWriteException(message: 'Hue/saturation adjustments require exactly six ranges');
  }
  writer
    ..writeUint16(adjustment.version)
    ..writeUint8(adjustment.colorize ? 1 : 0)
    ..writeUint8(0);
  _writeHueValues(writer, adjustment.colorization);
  _writeHueValues(writer, adjustment.master);
  for (final PsdHueSaturationRange range in adjustment.ranges) {
    if (range.boundaries.length != 4) {
      throw const PsWriteException(message: 'Each hue/saturation range requires four boundaries');
    }
    range.boundaries.forEach(writer.writeInt16);
    _writeHueValues(writer, range.values);
  }
  writer.writeBytes(adjustment.trailingData);
}

/// Writes one HSL triplet.
void _writeHueValues(PsBinaryWriter writer, PsdHueSaturationValues values) {
  writer
    ..writeInt16(values.hue)
    ..writeInt16(values.saturation)
    ..writeInt16(values.lightness);
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

/// Writes four channel-mixer output rows.
void _writeChannelMixer(PsBinaryWriter writer, PsdChannelMixerAdjustment adjustment) {
  if (adjustment.outputs.length != 4 || adjustment.outputs.any((output) => output.channels.length != 4)) {
    throw const PsWriteException(message: 'Channel mixer adjustments require four output rows of four channels');
  }
  writer
    ..writeUint16(adjustment.version)
    ..writeUint16(adjustment.monochrome ? 1 : 0);
  for (final PsdChannelMixerOutput output in adjustment.outputs) {
    output.channels.forEach(writer.writeInt16);
    writer.writeInt16(output.constant);
  }
  writer.writeBytes(adjustment.trailingData);
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

/// Writes ten selective-color correction records.
void _writeSelectiveColor(PsBinaryWriter writer, PsdSelectiveColorAdjustment adjustment) {
  if (adjustment.corrections.length != 10) {
    throw const PsWriteException(message: 'Selective color adjustments require exactly ten correction records');
  }
  writer
    ..writeUint16(adjustment.version)
    ..writeUint16(adjustment.absolute ? 1 : 0);
  for (final PsdSelectiveColorCorrection correction in adjustment.corrections) {
    writer
      ..writeInt16(correction.cyan)
      ..writeInt16(correction.magenta)
      ..writeInt16(correction.yellow)
      ..writeInt16(correction.black);
  }
  writer.writeBytes(adjustment.trailingData);
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

/// Converts a floating-point value to signed 16.16 fixed point.
int _fixed(double value) => (value * 65536).round();

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
