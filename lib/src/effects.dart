import 'dart:typed_data';

import 'package:pscore/pscore.dart';

part 'effects/layer_effects.dart';
part 'effects/legacy_codec.dart';
part 'effects/paint.dart';

/// Identifies a Photoshop layer-effect family.
enum PsdLayerEffectType {
  /// A shadow cast outside the layer.
  dropShadow(PsLayerEffectKind.dropShadow),

  /// A shadow cast inside the layer.
  innerShadow(PsLayerEffectKind.innerShadow),

  /// A glow outside the layer.
  outerGlow(PsLayerEffectKind.outerGlow),

  /// A glow inside the layer.
  innerGlow(PsLayerEffectKind.innerGlow),

  /// A bevel and emboss effect.
  bevelEmboss(PsLayerEffectKind.bevelAndEmboss),

  /// A satin shading effect.
  satin(PsLayerEffectKind.satin),

  /// A solid color overlay.
  colorOverlay(PsLayerEffectKind.colorOverlay),

  /// A gradient overlay.
  gradientOverlay(PsLayerEffectKind.gradientOverlay),

  /// A pattern overlay.
  patternOverlay(PsLayerEffectKind.patternOverlay),

  /// A layer stroke.
  stroke(PsLayerEffectKind.stroke),

  /// An effect whose descriptor class is not recognized yet.
  unknown(PsLayerEffectKind.unknown);

  /// Matching format-neutral effect family.
  final PsLayerEffectKind kind;

  /// Creates a type mirroring [kind].
  const PsdLayerEffectType(this.kind);

  /// Returns the type mirroring a format-neutral [kind].
  static PsdLayerEffectType fromKind(PsLayerEffectKind kind) => values.firstWhere((type) => type.kind == kind);
}

/// Backward-compatible name for the shared stroke placement.
typedef PsdStrokePosition = PsStrokePosition;

/// Backward-compatible name for the shared gradient geometry.
typedef PsdGradientStyle = PsGradientStyle;

/// Encodes and decodes modern `lfx2` and historical `lrFX` records.
abstract final class PsdLayerEffectsCodec {
  /// Decodes [bytes], returning `null` for malformed or unsupported data.
  static PsdLayerEffects? tryDecode(Uint8List bytes, {String key = 'lfx2'}) {
    try {
      return decode(bytes, key: key);
    } on FormatException {
      return null;
    }
  }

  /// Decodes one complete effects tagged-block payload.
  static PsdLayerEffects decode(Uint8List bytes, {String key = 'lfx2'}) {
    if (key == 'lrFX') {
      return _decodeLegacyEffects(bytes);
    }
    final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
    final int version = reader.readUint32();
    final int descriptorVersion = reader.readUint32();
    final ({PsDescriptor descriptor, int bytesRead}) decoded = PsDescriptorCodec.decodePrefix(Uint8List.sublistView(bytes, reader.offset));
    reader.skip(decoded.bytesRead);
    return PsdLayerEffects(
      version: version,
      descriptorVersion: descriptorVersion,
      descriptor: decoded.descriptor,
      blockKey: key,
      trailingData: reader.readBytes(reader.remaining),
    );
  }

  /// Encodes [effects] as either its retained legacy data or a modern payload.
  static Uint8List encode(PsdLayerEffects effects) {
    final Uint8List? legacy = effects._legacyData;
    if (effects.blockKey == 'lrFX' && legacy != null) {
      return Uint8List.fromList(legacy);
    }
    return (PsBinaryWriter()
          ..writeUint32(effects.version)
          ..writeUint32(effects.descriptorVersion)
          ..writeBytes(PsDescriptorCodec.encode(effects.descriptor))
          ..writeBytes(effects.trailingData))
        .takeBytes();
  }
}
