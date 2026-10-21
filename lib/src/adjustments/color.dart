part of '../adjustments.dart';

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
