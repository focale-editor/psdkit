import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:psdkit/src/fill_content.dart';

part 'adjustments/codec.dart';
part 'adjustments/color.dart';
part 'adjustments/gradient_map.dart';
part 'adjustments/other.dart';
part 'adjustments/tone.dart';

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
