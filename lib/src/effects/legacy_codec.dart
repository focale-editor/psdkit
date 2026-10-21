part of '../effects.dart';

/// Builds a modern semantic descriptor from a historical `lrFX` payload.
PsdLayerEffects _decodeLegacyEffects(Uint8List bytes) {
  final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
  final int version = reader.readUint16();
  if (version != 0) {
    throw FormatException('Unsupported lrFX version $version');
  }
  final int count = reader.readUint16();
  final List<PsdLayerEffect> effects = <PsdLayerEffect>[];
  bool enabled = true;
  for (int index = 0; index < count; index++) {
    if (reader.readString(4) != '8BIM') {
      throw const FormatException('Invalid lrFX effect signature');
    }
    final String key = reader.readString(4);
    final int length = reader.readLength(wide: false, label: 'legacy effect');
    final PsBinaryReader effect = reader.readReader(length);
    if (key == 'cmnS') {
      effect.readUint32();
      enabled = effect.readUint8() != 0;
    } else if (_decodeLegacyEffect(key, effect) case final PsdLayerEffect decoded) {
      effects.add(decoded);
    }
  }
  final PsdLayerEffects modern = PsdLayerEffects.create(effects: effects, enabled: enabled);
  return PsdLayerEffects._legacy(descriptor: modern.descriptor, data: Uint8List.fromList(bytes));
}

/// Decodes one historical effect payload identified by [key].
PsdLayerEffect? _decodeLegacyEffect(String key, PsBinaryReader reader) => switch (key) {
  'dsdw' => _decodeLegacyShadow(reader, PsdLayerEffectType.dropShadow),
  'isdw' => _decodeLegacyShadow(reader, PsdLayerEffectType.innerShadow),
  'oglw' => _decodeLegacyGlow(reader, PsdLayerEffectType.outerGlow),
  'iglw' => _decodeLegacyGlow(reader, PsdLayerEffectType.innerGlow),
  'sofi' => _decodeLegacySolidFill(reader),
  'bevl' => _decodeLegacyBevel(reader),
  _ => null,
};

/// Decodes a historical outer or inner shadow.
PsdLayerEffect _decodeLegacyShadow(PsBinaryReader reader, PsdLayerEffectType type) {
  reader.readUint32();
  final double size = _readLegacyFixed(reader);
  final double spread = _readLegacyFixed(reader);
  final double angle = _readLegacyFixed(reader);
  final double distance = _readLegacyFixed(reader);
  final PsdEffectColor fallback = _readLegacyColor(reader);
  reader.readString(4);
  final String blendMode = reader.readString(4);
  final bool enabled = reader.readUint8() != 0;
  final bool global = reader.readUint8() != 0;
  final int opacity = reader.readUint8();
  final PsdEffectColor native = _readLegacyColor(reader, fallback: fallback);
  return PsdLayerEffect.create(
    type: type,
    enabled: enabled,
    blendMode: blendMode,
    opacity: opacity * 100 / 255,
    color: native,
    size: size,
    spread: spread,
    angle: angle,
    distance: distance,
    useGlobalAngle: global,
  );
}

/// Decodes a historical outer or inner glow.
PsdLayerEffect _decodeLegacyGlow(PsBinaryReader reader, PsdLayerEffectType type) {
  reader.readUint32();
  final double size = _readLegacyFixed(reader);
  final double spread = _readLegacyFixed(reader);
  final PsdEffectColor fallback = _readLegacyColor(reader);
  reader.readString(4);
  final String blendMode = reader.readString(4);
  final bool enabled = reader.readUint8() != 0;
  final int opacity = reader.readUint8();
  if (type == PsdLayerEffectType.innerGlow) {
    reader.readUint8();
  }
  final PsdEffectColor native = _readLegacyColor(reader, fallback: fallback);
  return PsdLayerEffect.create(
    type: type,
    enabled: enabled,
    blendMode: blendMode,
    opacity: opacity * 100 / 255,
    color: native,
    size: size,
    spread: spread,
  );
}

/// Decodes a historical solid color overlay.
PsdLayerEffect _decodeLegacySolidFill(PsBinaryReader reader) {
  reader.readUint32();
  reader.readString(4);
  final String blendMode = reader.readString(4);
  final PsdEffectColor fallback = _readLegacyColor(reader);
  final int opacity = reader.readUint8();
  final bool enabled = reader.readUint8() != 0;
  final PsdEffectColor native = _readLegacyColor(reader, fallback: fallback);
  return PsdLayerEffect.create(
    type: PsdLayerEffectType.colorOverlay,
    enabled: enabled,
    blendMode: blendMode,
    opacity: opacity * 100 / 255,
    color: native,
  );
}

/// Decodes the common semantic portion of a historical bevel effect.
PsdLayerEffect _decodeLegacyBevel(PsBinaryReader reader) {
  reader.readUint32();
  final double angle = _readLegacyFixed(reader);
  final double strength = _readLegacyFixed(reader);
  final double size = _readLegacyFixed(reader);
  reader.skip(16);
  final PsdEffectColor highlight = _readLegacyColor(reader);
  _readLegacyColor(reader);
  reader.skip(3);
  final bool enabled = reader.readUint8() != 0;
  final bool global = reader.readUint8() != 0;
  reader.readUint8();
  final PsdEffectColor nativeHighlight = _readLegacyColor(reader, fallback: highlight);
  return PsdLayerEffect.create(
    type: PsdLayerEffectType.bevelEmboss,
    enabled: enabled,
    opacity: strength,
    color: nativeHighlight,
    size: size,
    angle: angle,
    useGlobalAngle: global,
  );
}

/// Reads one historical 16.16 fixed-point pixel, degree, or percent value.
///
/// Photoshop 5.0 effect records store these quantities scaled by 65536, so a
/// seven-pixel blur is written as `458752`.
double _readLegacyFixed(PsBinaryReader reader) => reader.readInt32() / 65536;

/// Reads a ten-byte Photoshop legacy color record.
PsdEffectColor _readLegacyColor(PsBinaryReader reader, {PsdEffectColor fallback = PsdEffectColor.black}) {
  final int space = reader.readUint16();
  final List<int> components = <int>[for (int index = 0; index < 4; index++) reader.readUint16()];
  if (space != 0) {
    return fallback;
  }
  return PsdEffectColor(alpha: 255, red: (components[0] / 257).round(), green: (components[1] / 257).round(), blue: (components[2] / 257).round());
}
