import 'dart:typed_data';

import 'package:pscore/pscore.dart';

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

/// An RGBA color used by a layer effect.
final class PsdEffectColor {
  /// Alpha component from 0 through 255.
  final int alpha;

  /// Red component from 0 through 255.
  final int red;

  /// Green component from 0 through 255.
  final int green;

  /// Blue component from 0 through 255.
  final int blue;

  /// Opaque black.
  static const PsdEffectColor black = PsdEffectColor(alpha: 255, red: 0, green: 0, blue: 0);

  /// Creates an effect color.
  const PsdEffectColor({required this.alpha, required this.red, required this.green, required this.blue});

  /// The color packed as an ARGB integer.
  int get argb => alpha << 24 | red << 16 | green << 8 | blue;

  /// Returns an opaque color from an RGB [color], or `null` for other spaces.
  static PsdEffectColor? fromColor(PsColor color) {
    final double? red = color.red;
    final double? green = color.green;
    final double? blue = color.blue;
    if (red == null || green == null || blue == null) {
      return null;
    }
    return PsdEffectColor(alpha: 255, red: red.clamp(0, 255).round(), green: green.clamp(0, 255).round(), blue: blue.clamp(0, 255).round());
  }

  /// Converts this color to a Photoshop RGB color descriptor view.
  PsColor toColor() => PsColor.rgb(red: red.toDouble(), green: green.toDouble(), blue: blue.toDouble());
}

/// One color stop in a Photoshop gradient.
final class PsdGradientColorStop {
  /// Stop color.
  final PsdEffectColor color;

  /// Position from 0 through 4096.
  final int location;

  /// Midpoint percentage between this stop and the next one.
  final int midpoint;

  /// Creates a gradient color stop.
  const PsdGradientColorStop({required this.color, required this.location, this.midpoint = 50});
}

/// One opacity stop in a Photoshop gradient.
final class PsdGradientOpacityStop {
  /// Opacity percentage from 0 through 100.
  final double opacity;

  /// Position from 0 through 4096.
  final int location;

  /// Midpoint percentage between this stop and the next one.
  final int midpoint;

  /// Creates a gradient opacity stop.
  const PsdGradientOpacityStop({required this.opacity, required this.location, this.midpoint = 50});
}

/// A Photoshop custom gradient used by an effect.
final class PsdEffectGradient {
  /// Display name stored by Photoshop.
  final String name;

  /// Ordered color stops.
  final List<PsdGradientColorStop> colors;

  /// Ordered opacity stops.
  final List<PsdGradientOpacityStop> opacities;

  /// Creates a custom effect gradient.
  const PsdEffectGradient({this.name = 'Custom', required this.colors, this.opacities = const <PsdGradientOpacityStop>[]});

  /// Returns the RGB custom stops of [gradient], skipping non-RGB colors.
  factory PsdEffectGradient.fromGradient(PsGradient gradient) => PsdEffectGradient(
    name: gradient.name ?? '',
    colors: [
      for (final PsGradientColorStop stop in gradient.colorStops)
        if (stop.color case final PsColor color)
          if (PsdEffectColor.fromColor(color) case final PsdEffectColor rgb)
            PsdGradientColorStop(
              color: rgb,
              location: stop.location ?? 0,
              midpoint: stop.midpoint ?? 50,
            ),
    ],
    opacities: [
      for (final PsGradientTransparencyStop stop in gradient.transparencyStops)
        PsdGradientOpacityStop(
          opacity: stop.opacity?.value ?? 100,
          location: stop.location ?? 0,
          midpoint: stop.midpoint ?? 50,
        ),
    ],
  );

  /// Converts this gradient to a Photoshop custom-stops gradient view.
  PsGradient toGradient() => PsGradient.custom(
    name: name,
    colorStops: [
      for (final PsdGradientColorStop stop in colors) PsGradientColorStop.create(color: stop.color.toColor(), location: stop.location, midpoint: stop.midpoint),
    ],
    transparencyStops: [
      for (final PsdGradientOpacityStop stop in opacities) PsGradientTransparencyStop.create(opacity: stop.opacity, location: stop.location, midpoint: stop.midpoint),
    ],
  );
}

/// A Photoshop pattern reference used by a layer effect.
final class PsdEffectPattern {
  /// Human-readable pattern name.
  final String name;

  /// Photoshop pattern UUID or identifier.
  final String id;

  /// Creates a pattern reference.
  const PsdEffectPattern({required this.name, required this.id});

  /// Converts this reference to a Photoshop pattern reference view.
  PsPatternReference toReference() => PsPatternReference.create(name: name, id: id);
}

/// One semantic Photoshop effect backed by its complete action descriptor.
final class PsdLayerEffect {
  /// Recognized effect family.
  final PsdLayerEffectType type;

  /// Complete descriptor, including properties not interpreted by PsdKit.
  final PsDescriptor descriptor;

  /// Creates an effect view over an existing [descriptor].
  const PsdLayerEffect({required this.type, required this.descriptor});

  /// Creates a common effect with editable core properties.
  factory PsdLayerEffect.create({
    required PsdLayerEffectType type,
    bool enabled = true,
    String blendMode = 'Nrml',
    double opacity = 100,
    PsdEffectColor color = PsdEffectColor.black,
    double size = 5,
    double angle = 90,
    double distance = 0,
    double spread = 0,
    double noise = 0,
    bool useGlobalAngle = true,
    PsdStrokePosition strokePosition = PsdStrokePosition.outside,
    PsdEffectGradient? gradient,
    PsdGradientStyle gradientStyle = PsdGradientStyle.linear,
    PsdEffectPattern? pattern,
    bool reverse = false,
    bool dither = false,
    bool aligned = true,
    double scale = 100,
    double offsetX = 0,
    double offsetY = 0,
  }) {
    if (type == PsdLayerEffectType.unknown) {
      // Unknown effects have no Photoshop class, so they keep a bare record.
      return PsdLayerEffect(
        type: type,
        descriptor: PsDescriptor(
          name: '\u0000',
          classId: 'null',
          items: [
            PsDescriptorItem(
              key: 'enab',
              value: PsBooleanValue(value: enabled),
            ),
            const PsDescriptorItem(key: 'present', value: PsBooleanValue(value: true)),
            const PsDescriptorItem(key: 'showInDialog', value: PsBooleanValue(value: true)),
            PsDescriptorItem(
              key: 'Md  ',
              value: PsEnumeratedValue(typeId: 'BlnM', value: blendMode),
            ),
            PsDescriptorItem(
              key: 'Opct',
              value: PsUnitFloatValue(unit: '#Prc', value: opacity),
            ),
          ],
        ),
      );
    }
    final PsLayerEffect effect = PsLayerEffect.create(
      kind: type.kind,
      enabled: enabled,
      blendMode: blendMode,
      opacity: opacity,
      color: color.toColor(),
      size: size,
      angle: angle,
      distance: distance,
      spread: spread,
      noise: noise,
      useGlobalAngle: useGlobalAngle,
      strokePosition: strokePosition,
      gradient: gradient?.toGradient(),
      gradientStyle: gradientStyle,
      pattern: pattern?.toReference(),
      reverse: reverse,
      dither: dither,
      aligned: aligned,
      scale: scale,
      offsetX: offsetX,
      offsetY: offsetY,
    );
    return PsdLayerEffect(type: type, descriptor: effect.descriptor);
  }

  /// Complete format-neutral view, including every non-RGB color space.
  PsLayerEffect get view => PsLayerEffect(key: type.kind.rootKey ?? descriptor.classId, instanceIndex: 0, kind: type.kind, descriptor: descriptor);

  /// Whether the individual effect is enabled.
  bool get enabled => descriptor.booleanValue('enab') ?? true;

  /// Photoshop blend-mode identifier such as `Nrml` or `Mltp`.
  String get blendMode => descriptor.enumerationIdentifier('Md  ') ?? descriptor.enumerationIdentifier('hglM') ?? 'Nrml';

  /// Effect opacity percentage.
  double get opacity => descriptor.scalarValue('Opct') ?? descriptor.scalarValue('hglO') ?? 100;

  /// Primary effect color, when the effect uses an RGB one.
  PsdEffectColor? get color => _rgb(view.color) ?? _rgb(view.highlightColor);

  /// Blur or stroke size in pixels, when applicable.
  double? get size => descriptor.scalarValue(type == PsdLayerEffectType.stroke ? 'Sz  ' : 'blur');

  /// Lighting or gradient angle in degrees, when applicable.
  double? get angle => descriptor.scalarValue(descriptor.value('lagl') == null ? 'Angl' : 'lagl');

  /// Shadow distance in pixels, when applicable.
  double? get distance => descriptor.scalarValue('Dstn');

  /// Shadow spread or glow choke in pixels.
  double? get spread => descriptor.scalarValue('Ckmt');

  /// Noise percentage, when applicable.
  double? get noise => descriptor.scalarValue('Nose');

  /// Whether the effect follows the document-wide lighting angle.
  bool get useGlobalAngle => descriptor.booleanValue('uglg') ?? false;

  /// Stroke placement, when this is a stroke effect.
  PsdStrokePosition? get strokePosition => type == PsdLayerEffectType.stroke ? PsStrokePosition.fromIdentifier(descriptor.enumerationIdentifier('Styl')) : null;

  /// Custom gradient, when this effect contains one.
  PsdEffectGradient? get gradient => switch (view.gradient) {
    final PsGradient gradient => PsdEffectGradient.fromGradient(gradient),
    null => null,
  };

  /// Gradient geometry, when this is a gradient effect.
  PsdGradientStyle? get gradientStyle => descriptor.value('Grad') == null ? null : PsGradientStyle.fromIdentifier(descriptor.enumerationIdentifier('Type'));

  /// Pattern reference, when this effect contains one.
  PsdEffectPattern? get pattern => switch (view.pattern) {
    final PsPatternReference pattern => PsdEffectPattern(name: pattern.name ?? '', id: pattern.id ?? ''),
    null => null,
  };

  /// Returns a copy with one raw descriptor property replaced.
  PsdLayerEffect withProperty(String key, PsDescriptorValue value) => PsdLayerEffect(type: type, descriptor: descriptor.withValue(key, value));

  /// Returns a copy whose enabled state is [value].
  PsdLayerEffect withEnabled(bool value) => withProperty('enab', PsBooleanValue(value: value));

  /// Returns a copy whose opacity percentage is [value].
  PsdLayerEffect withOpacity(double value) => withProperty(
    type == PsdLayerEffectType.bevelEmboss ? 'hglO' : 'Opct',
    PsUnitFloatValue(unit: '#Prc', value: value),
  );

  /// Returns a copy whose primary color is [value].
  PsdLayerEffect withColor(PsdEffectColor value) => withProperty(
    type == PsdLayerEffectType.bevelEmboss ? 'hglC' : 'Clr ',
    PsObjectValue(value: value.toColor().descriptor),
  );

  /// Converts an optional [color] to RGB.
  static PsdEffectColor? _rgb(PsColor? color) => color == null ? null : PsdEffectColor.fromColor(color);
}

/// A complete editable modern or imported legacy layer-effects record.
final class PsdLayerEffects {
  /// Effects record version, normally zero.
  final int version;

  /// Action-descriptor version, normally 16.
  final int descriptorVersion;

  /// Complete modern effects descriptor.
  final PsDescriptor descriptor;

  /// Original tagged-block key, normally `lfx2` or `lrFX`.
  final String blockKey;

  /// Bytes following the action descriptor in the tagged block.
  final Uint8List trailingData;

  /// Original legacy payload retained for an unchanged `lrFX` record.
  final Uint8List? _legacyData;

  /// Creates editable modern layer effects.
  PsdLayerEffects({
    required this.descriptor,
    this.version = 0,
    this.descriptorVersion = 16,
    this.blockKey = 'lfx2',
    Uint8List? trailingData,
  }) : trailingData = trailingData ?? Uint8List(0),
       _legacyData = null;

  /// Creates a modern effects record from semantic [effects].
  factory PsdLayerEffects.create({List<PsdLayerEffect> effects = const <PsdLayerEffect>[], bool enabled = true, double scale = 100}) {
    final PsdLayerEffects empty = PsdLayerEffects(
      descriptor: PsDescriptor(
        name: '\u0000',
        classId: 'null',
        items: <PsDescriptorItem>[
          PsDescriptorItem(
            key: 'Scl ',
            value: PsUnitFloatValue(unit: '#Prc', value: scale),
          ),
          PsDescriptorItem(
            key: 'masterFXSwitch',
            value: PsBooleanValue(value: enabled),
          ),
        ],
      ),
    );
    return empty.withEffects(effects);
  }

  /// Creates a semantic modern view retaining [data] for legacy round trips.
  PsdLayerEffects._legacy({required this.descriptor, required Uint8List data}) : version = 0, descriptorVersion = 16, blockKey = 'lrFX', trailingData = Uint8List(0), _legacyData = data;

  /// Complete format-neutral view, including every non-RGB color space.
  PsLayerEffects get view => PsLayerEffects.fromDescriptor(descriptor);

  /// Whether all layer effects are enabled globally.
  bool get enabled => descriptor.booleanValue('masterFXSwitch') ?? true;

  /// Global effect scale percentage.
  double get scale => descriptor.scalarValue('Scl ') ?? 100;

  /// Effects in descriptor order, including repeated effect families.
  List<PsdLayerEffect> get effects => [
    for (final PsLayerEffect effect in view.effects)
      if (effect.kind != PsLayerEffectKind.unknown) PsdLayerEffect(type: PsdLayerEffectType.fromKind(effect.kind), descriptor: effect.descriptor),
  ];

  /// Returns a modern record containing [effects] and preserving other root keys.
  PsdLayerEffects withEffects(List<PsdLayerEffect> effects) {
    final List<PsDescriptorItem> items = <PsDescriptorItem>[
      for (final PsDescriptorItem item in descriptor.items)
        if (PsLayerEffectKind.fromKey(item.key) == PsLayerEffectKind.unknown) item,
      ...PsLayerEffects.rootItems([for (final PsdLayerEffect effect in effects) (kind: effect.type.kind, descriptor: effect.descriptor)]),
    ];
    return PsdLayerEffects(
      version: version,
      descriptorVersion: descriptorVersion,
      descriptor: PsDescriptor(name: descriptor.name, classId: descriptor.classId, items: items),
      trailingData: blockKey == 'lrFX' ? null : trailingData,
    );
  }

  /// Returns a copy whose global enabled state is [value].
  PsdLayerEffects withEnabled(bool value) => PsdLayerEffects(
    version: version,
    descriptorVersion: descriptorVersion,
    descriptor: descriptor.withValue('masterFXSwitch', PsBooleanValue(value: value)),
    blockKey: blockKey == 'lrFX' ? 'lfx2' : blockKey,
    trailingData: blockKey == 'lrFX' ? null : trailingData,
  );
}

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
