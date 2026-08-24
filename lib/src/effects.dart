import 'dart:typed_data';

import 'package:pscore/pscore.dart';

/// Identifies a Photoshop layer-effect family.
enum PsdLayerEffectType {
  /// A shadow cast outside the layer.
  dropShadow,

  /// A shadow cast inside the layer.
  innerShadow,

  /// A glow outside the layer.
  outerGlow,

  /// A glow inside the layer.
  innerGlow,

  /// A bevel and emboss effect.
  bevelEmboss,

  /// A satin shading effect.
  satin,

  /// A solid color overlay.
  colorOverlay,

  /// A gradient overlay.
  gradientOverlay,

  /// A pattern overlay.
  patternOverlay,

  /// A layer stroke.
  stroke,

  /// An effect whose descriptor class is not recognized yet.
  unknown,
}

/// Placement of a Photoshop layer stroke.
enum PsdStrokePosition {
  /// Draws the stroke inside the layer edge.
  inside,

  /// Centers the stroke on the layer edge.
  center,

  /// Draws the stroke outside the layer edge.
  outside,
}

/// Geometry used by a gradient effect.
enum PsdGradientStyle {
  /// A straight linear gradient.
  linear,

  /// A radial gradient.
  radial,

  /// An angle gradient.
  angle,

  /// A reflected linear gradient.
  reflected,

  /// A diamond gradient.
  diamond,
}

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
}

/// A Photoshop pattern reference used by a layer effect.
final class PsdEffectPattern {
  /// Human-readable pattern name.
  final String name;

  /// Photoshop pattern UUID or identifier.
  final String id;

  /// Creates a pattern reference.
  const PsdEffectPattern({required this.name, required this.id});
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
    final List<PsDescriptorItem> items = <PsDescriptorItem>[
      PsDescriptorItem(
        key: 'enab',
        value: PsBooleanValue(value: enabled),
      ),
      const PsDescriptorItem(key: 'present', value: PsBooleanValue(value: true)),
      const PsDescriptorItem(key: 'showInDialog', value: PsBooleanValue(value: true)),
    ];
    _appendEffectProperties(
      items,
      type: type,
      blendMode: blendMode,
      opacity: opacity,
      color: color,
      size: size,
      angle: angle,
      distance: distance,
      spread: spread,
      noise: noise,
      useGlobalAngle: useGlobalAngle,
      strokePosition: strokePosition,
      gradient: gradient,
      gradientStyle: gradientStyle,
      pattern: pattern,
      reverse: reverse,
      dither: dither,
      aligned: aligned,
      scale: scale,
      offsetX: offsetX,
      offsetY: offsetY,
    );
    return PsdLayerEffect(
      type: type,
      descriptor: PsDescriptor(name: '\u0000', classId: _effectClassId(type), items: items),
    );
  }

  /// Whether the individual effect is enabled.
  bool get enabled => _boolValue(descriptor, 'enab') ?? true;

  /// Photoshop blend-mode identifier such as `Nrml` or `Mltp`.
  String get blendMode => _enumValue(descriptor, 'Md  ') ?? _enumValue(descriptor, 'hglM') ?? 'Nrml';

  /// Effect opacity percentage.
  double get opacity => _numberValue(descriptor, 'Opct') ?? _numberValue(descriptor, 'hglO') ?? 100;

  /// Primary effect color, when the effect uses one.
  PsdEffectColor? get color => _colorValue(descriptor.value('Clr ')) ?? _colorValue(descriptor.value('hglC'));

  /// Blur or stroke size in pixels, when applicable.
  double? get size => _numberValue(descriptor, type == PsdLayerEffectType.stroke ? 'Sz  ' : 'blur');

  /// Lighting or gradient angle in degrees, when applicable.
  double? get angle => _numberValue(descriptor, descriptor.value('lagl') == null ? 'Angl' : 'lagl');

  /// Shadow distance in pixels, when applicable.
  double? get distance => _numberValue(descriptor, 'Dstn');

  /// Shadow spread or glow choke in pixels.
  double? get spread => _numberValue(descriptor, 'Ckmt');

  /// Noise percentage, when applicable.
  double? get noise => _numberValue(descriptor, 'Nose');

  /// Whether the effect follows the document-wide lighting angle.
  bool get useGlobalAngle => _boolValue(descriptor, 'uglg') ?? false;

  /// Stroke placement, when this is a stroke effect.
  PsdStrokePosition? get strokePosition {
    if (type != PsdLayerEffectType.stroke) {
      return null;
    }
    return switch (_enumValue(descriptor, 'Styl')) {
      'InsF' => PsdStrokePosition.inside,
      'CtrF' => PsdStrokePosition.center,
      _ => PsdStrokePosition.outside,
    };
  }

  /// Custom gradient, when this effect contains one.
  PsdEffectGradient? get gradient => _gradientValue(descriptor.value('Grad'));

  /// Gradient geometry, when this is a gradient effect.
  PsdGradientStyle? get gradientStyle {
    if (descriptor.value('Grad') == null) {
      return null;
    }
    return switch (_enumValue(descriptor, 'Type')) {
      'Rdl ' => PsdGradientStyle.radial,
      'Angl' => PsdGradientStyle.angle,
      'Rflc' => PsdGradientStyle.reflected,
      'Dmnd' => PsdGradientStyle.diamond,
      _ => PsdGradientStyle.linear,
    };
  }

  /// Pattern reference, when this effect contains one.
  PsdEffectPattern? get pattern => _patternValue(descriptor.value('Ptrn'));

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
    PsObjectValue(value: _colorDescriptor(value)),
  );
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

  /// Whether all layer effects are enabled globally.
  bool get enabled => _boolValue(descriptor, 'masterFXSwitch') ?? true;

  /// Global effect scale percentage.
  double get scale => _numberValue(descriptor, 'Scl ') ?? 100;

  /// Effects in descriptor order, including repeated effect families.
  List<PsdLayerEffect> get effects => _readEffects(descriptor);

  /// Returns a modern record containing [effects] and preserving other root keys.
  PsdLayerEffects withEffects(List<PsdLayerEffect> effects) {
    final List<PsDescriptorItem> items = <PsDescriptorItem>[
      for (final PsDescriptorItem item in descriptor.items)
        if (!_effectRootKeys.contains(item.key)) item,
      ..._writeEffectItems(effects),
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

/// Root descriptor keys containing one or more layer effects.
const Set<String> _effectRootKeys = <String>{
  'DrSh',
  'dropShadowMulti',
  'IrSh',
  'innerShadowMulti',
  'OrGl',
  'outerGlowMulti',
  'IrGl',
  'innerGlowMulti',
  'ebbl',
  'bevelEmbossMulti',
  'ChFX',
  'satinMulti',
  'SoFi',
  'solidFillMulti',
  'GrFl',
  'gradientFillMulti',
  'patternFill',
  'patternFillMulti',
  'FrFX',
  'frameFXMulti',
};

/// Reads every recognized effect from [descriptor].
List<PsdLayerEffect> _readEffects(PsDescriptor descriptor) {
  final List<PsdLayerEffect> result = <PsdLayerEffect>[];
  for (final PsDescriptorItem item in descriptor.items) {
    final PsdLayerEffectType? type = _effectTypeForRootKey(item.key);
    if (type == null) {
      continue;
    }
    switch (item.value) {
      case PsObjectValue(:final PsDescriptor value):
        result.add(PsdLayerEffect(type: type, descriptor: value));
      case PsListValue(:final List<PsDescriptorValue> values):
        for (final PsDescriptorValue value in values) {
          if (value case PsObjectValue(:final PsDescriptor value)) {
            result.add(PsdLayerEffect(type: type, descriptor: value));
          }
        }
      default:
        break;
    }
  }
  return result;
}

/// Serializes semantic [effects] into singular or multi-effect root items.
List<PsDescriptorItem> _writeEffectItems(List<PsdLayerEffect> effects) {
  final List<PsDescriptorItem> result = <PsDescriptorItem>[];
  for (final PsdLayerEffectType type in PsdLayerEffectType.values) {
    if (type == PsdLayerEffectType.unknown) {
      continue;
    }
    final List<PsdLayerEffect> matches = effects.where((effect) => effect.type == type).toList();
    if (matches.isEmpty) {
      continue;
    }
    if (matches.length == 1) {
      result.add(
        PsDescriptorItem(
          key: _effectRootKey(type),
          value: PsObjectValue(value: matches.single.descriptor),
        ),
      );
    } else {
      result.add(
        PsDescriptorItem(
          key: _effectMultiRootKey(type),
          value: PsListValue(values: <PsDescriptorValue>[for (final PsdLayerEffect effect in matches) PsObjectValue(value: effect.descriptor)]),
        ),
      );
    }
  }
  return result;
}

/// Adds properties required by the selected effect [type].
void _appendEffectProperties(
  List<PsDescriptorItem> items, {
  required PsdLayerEffectType type,
  required String blendMode,
  required double opacity,
  required PsdEffectColor color,
  required double size,
  required double angle,
  required double distance,
  required double spread,
  required double noise,
  required bool useGlobalAngle,
  required PsdStrokePosition strokePosition,
  required PsdEffectGradient? gradient,
  required PsdGradientStyle gradientStyle,
  required PsdEffectPattern? pattern,
  required bool reverse,
  required bool dither,
  required bool aligned,
  required double scale,
  required double offsetX,
  required double offsetY,
}) {
  if (type != PsdLayerEffectType.bevelEmboss) {
    items
      ..add(
        PsDescriptorItem(
          key: 'Md  ',
          value: PsEnumeratedValue(typeId: 'BlnM', value: blendMode),
        ),
      )
      ..add(
        PsDescriptorItem(
          key: 'Opct',
          value: PsUnitFloatValue(unit: '#Prc', value: opacity),
        ),
      );
  }
  switch (type) {
    case PsdLayerEffectType.dropShadow || PsdLayerEffectType.innerShadow:
      items
        ..add(
          PsDescriptorItem(
            key: 'Clr ',
            value: PsObjectValue(value: _colorDescriptor(color)),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'uglg',
            value: PsBooleanValue(value: useGlobalAngle),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'lagl',
            value: PsUnitFloatValue(unit: '#Ang', value: angle),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'Dstn',
            value: PsUnitFloatValue(unit: '#Pxl', value: distance),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'Ckmt',
            value: PsUnitFloatValue(unit: '#Pxl', value: spread),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'blur',
            value: PsUnitFloatValue(unit: '#Pxl', value: size),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'Nose',
            value: PsUnitFloatValue(unit: '#Prc', value: noise),
          ),
        )
        ..add(const PsDescriptorItem(key: 'AntA', value: PsBooleanValue(value: false)))
        ..add(
          PsDescriptorItem(
            key: 'TrnS',
            value: PsObjectValue(value: _linearContourDescriptor()),
          ),
        )
        ..add(const PsDescriptorItem(key: 'layerConceals', value: PsBooleanValue(value: true)));
    case PsdLayerEffectType.outerGlow || PsdLayerEffectType.innerGlow:
      items
        ..add(
          PsDescriptorItem(
            key: 'Clr ',
            value: PsObjectValue(value: _colorDescriptor(color)),
          ),
        )
        ..add(
          const PsDescriptorItem(
            key: 'GlwT',
            value: PsEnumeratedValue(typeId: 'BETE', value: 'SfBL'),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'Ckmt',
            value: PsUnitFloatValue(unit: '#Pxl', value: spread),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'blur',
            value: PsUnitFloatValue(unit: '#Pxl', value: size),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'Nose',
            value: PsUnitFloatValue(unit: '#Prc', value: noise),
          ),
        )
        ..add(
          const PsDescriptorItem(
            key: 'ShdN',
            value: PsUnitFloatValue(unit: '#Prc', value: 0),
          ),
        )
        ..add(const PsDescriptorItem(key: 'AntA', value: PsBooleanValue(value: false)))
        ..add(
          PsDescriptorItem(
            key: 'TrnS',
            value: PsObjectValue(value: _linearContourDescriptor()),
          ),
        )
        ..add(
          const PsDescriptorItem(
            key: 'Inpr',
            value: PsUnitFloatValue(unit: '#Prc', value: 50),
          ),
        );
      if (type == PsdLayerEffectType.innerGlow) {
        items.add(
          const PsDescriptorItem(
            key: 'glwS',
            value: PsEnumeratedValue(typeId: 'IGSr', value: 'SrcE'),
          ),
        );
      }
    case PsdLayerEffectType.colorOverlay:
      items.add(
        PsDescriptorItem(
          key: 'Clr ',
          value: PsObjectValue(value: _colorDescriptor(color)),
        ),
      );
    case PsdLayerEffectType.gradientOverlay:
      items
        ..add(
          PsDescriptorItem(
            key: 'Grad',
            value: PsObjectValue(value: _gradientDescriptor(gradient ?? _defaultGradient(color))),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'Angl',
            value: PsUnitFloatValue(unit: '#Ang', value: angle),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'Type',
            value: PsEnumeratedValue(typeId: 'GrdT', value: _gradientStyleId(gradientStyle)),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'Rvrs',
            value: PsBooleanValue(value: reverse),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'Dthr',
            value: PsBooleanValue(value: dither),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'Algn',
            value: PsBooleanValue(value: aligned),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'Scl ',
            value: PsUnitFloatValue(unit: '#Prc', value: scale),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'Ofst',
            value: PsObjectValue(value: _pointDescriptor(offsetX, offsetY, unit: '#Prc')),
          ),
        );
    case PsdLayerEffectType.patternOverlay:
      items
        ..add(
          PsDescriptorItem(
            key: 'Ptrn',
            value: PsObjectValue(
              value: _patternDescriptor(pattern ?? const PsdEffectPattern(name: '', id: '')),
            ),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'Scl ',
            value: PsUnitFloatValue(unit: '#Prc', value: scale),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'Algn',
            value: PsBooleanValue(value: aligned),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'phase',
            value: PsObjectValue(value: _pointDescriptor(offsetX, offsetY)),
          ),
        );
    case PsdLayerEffectType.stroke:
      final String fillType = gradient != null ? 'GrFl' : (pattern != null ? 'Ptrn' : 'SClr');
      items
        ..add(
          PsDescriptorItem(
            key: 'Styl',
            value: PsEnumeratedValue(typeId: 'FStl', value: _strokePositionId(strokePosition)),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'PntT',
            value: PsEnumeratedValue(typeId: 'FrFl', value: fillType),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'Sz  ',
            value: PsUnitFloatValue(unit: '#Pxl', value: size),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'Clr ',
            value: PsObjectValue(value: _colorDescriptor(color)),
          ),
        )
        ..add(const PsDescriptorItem(key: 'overprint', value: PsBooleanValue(value: false)));
      if (gradient != null) {
        items.add(
          PsDescriptorItem(
            key: 'Grad',
            value: PsObjectValue(value: _gradientDescriptor(gradient)),
          ),
        );
      } else if (pattern != null) {
        items.add(
          PsDescriptorItem(
            key: 'Ptrn',
            value: PsObjectValue(value: _patternDescriptor(pattern)),
          ),
        );
      }
    case PsdLayerEffectType.satin:
      items
        ..add(
          PsDescriptorItem(
            key: 'Clr ',
            value: PsObjectValue(value: _colorDescriptor(color)),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'lagl',
            value: PsUnitFloatValue(unit: '#Ang', value: angle),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'Dstn',
            value: PsUnitFloatValue(unit: '#Pxl', value: distance),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'blur',
            value: PsUnitFloatValue(unit: '#Pxl', value: size),
          ),
        )
        ..add(const PsDescriptorItem(key: 'AntA', value: PsBooleanValue(value: true)))
        ..add(const PsDescriptorItem(key: 'Invr', value: PsBooleanValue(value: false)))
        ..add(
          PsDescriptorItem(
            key: 'MpgS',
            value: PsObjectValue(value: _linearContourDescriptor()),
          ),
        );
    case PsdLayerEffectType.bevelEmboss:
      items
        ..add(
          const PsDescriptorItem(
            key: 'hglM',
            value: PsEnumeratedValue(typeId: 'BlnM', value: 'Scrn'),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'hglC',
            value: PsObjectValue(value: _colorDescriptor(color)),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'hglO',
            value: PsUnitFloatValue(unit: '#Prc', value: opacity),
          ),
        )
        ..add(
          const PsDescriptorItem(
            key: 'sdwM',
            value: PsEnumeratedValue(typeId: 'BlnM', value: 'Mltp'),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'sdwC',
            value: PsObjectValue(value: _colorDescriptor(PsdEffectColor.black)),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'sdwO',
            value: PsUnitFloatValue(unit: '#Prc', value: opacity),
          ),
        )
        ..add(
          const PsDescriptorItem(
            key: 'bvlT',
            value: PsEnumeratedValue(typeId: 'bvlT', value: 'SfBL'),
          ),
        )
        ..add(
          const PsDescriptorItem(
            key: 'bvlS',
            value: PsEnumeratedValue(typeId: 'BESl', value: 'InrB'),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'uglg',
            value: PsBooleanValue(value: useGlobalAngle),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'lagl',
            value: PsUnitFloatValue(unit: '#Ang', value: angle),
          ),
        )
        ..add(
          const PsDescriptorItem(
            key: 'Lald',
            value: PsUnitFloatValue(unit: '#Ang', value: 30),
          ),
        )
        ..add(
          const PsDescriptorItem(
            key: 'srgR',
            value: PsUnitFloatValue(unit: '#Prc', value: 100),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'blur',
            value: PsUnitFloatValue(unit: '#Pxl', value: size),
          ),
        )
        ..add(
          const PsDescriptorItem(
            key: 'bvlD',
            value: PsEnumeratedValue(typeId: 'BESs', value: 'In  '),
          ),
        )
        ..add(
          PsDescriptorItem(
            key: 'TrnS',
            value: PsObjectValue(value: _linearContourDescriptor()),
          ),
        )
        ..add(const PsDescriptorItem(key: 'antialiasGloss', value: PsBooleanValue(value: false)))
        ..add(
          const PsDescriptorItem(
            key: 'Sftn',
            value: PsUnitFloatValue(unit: '#Pxl', value: 0),
          ),
        )
        ..add(const PsDescriptorItem(key: 'useShape', value: PsBooleanValue(value: false)))
        ..add(const PsDescriptorItem(key: 'useTexture', value: PsBooleanValue(value: false)));
    case PsdLayerEffectType.unknown:
      break;
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
  final int size = reader.readInt32();
  final int spread = reader.readInt32();
  final int angle = reader.readInt32();
  final int distance = reader.readInt32();
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
    size: size.toDouble(),
    spread: spread.toDouble(),
    angle: angle.toDouble(),
    distance: distance.toDouble(),
    useGlobalAngle: global,
  );
}

/// Decodes a historical outer or inner glow.
PsdLayerEffect _decodeLegacyGlow(PsBinaryReader reader, PsdLayerEffectType type) {
  reader.readUint32();
  final int size = reader.readInt32();
  final int spread = reader.readInt32();
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
    size: size.toDouble(),
    spread: spread.toDouble(),
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
  final int angle = reader.readInt32();
  final int strength = reader.readInt32();
  final int size = reader.readInt32();
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
    opacity: strength.toDouble(),
    color: nativeHighlight,
    size: size.toDouble(),
    angle: angle.toDouble(),
    useGlobalAngle: global,
  );
}

/// Reads a ten-byte Photoshop legacy color record.
PsdEffectColor _readLegacyColor(PsBinaryReader reader, {PsdEffectColor fallback = PsdEffectColor.black}) {
  final int space = reader.readUint16();
  final List<int> components = <int>[for (int index = 0; index < 4; index++) reader.readUint16()];
  if (space != 0) {
    return fallback;
  }
  return PsdEffectColor(alpha: 255, red: (components[0] / 257).round(), green: (components[1] / 257).round(), blue: (components[2] / 257).round());
}

/// Reads a Boolean property from [descriptor].
bool? _boolValue(PsDescriptor descriptor, String key) => switch (descriptor.value(key)) {
  PsBooleanValue(:final bool value) => value,
  _ => null,
};

/// Reads a numeric property from [descriptor].
double? _numberValue(PsDescriptor descriptor, String key) => switch (descriptor.value(key)) {
  PsUnitFloatValue(:final double value) => value,
  PsDoubleValue(:final double value) => value,
  PsIntegerValue(:final int value) => value.toDouble(),
  _ => null,
};

/// Reads an enumeration identifier from [descriptor].
String? _enumValue(PsDescriptor descriptor, String key) => switch (descriptor.value(key)) {
  PsEnumeratedValue(:final String value) => value,
  _ => null,
};

/// Reads an RGB descriptor value.
PsdEffectColor? _colorValue(PsDescriptorValue? value) {
  if (value is! PsObjectValue) {
    return null;
  }
  final PsDescriptor color = value.value;
  final double? red = _numberValue(color, 'Rd  ');
  final double? green = _numberValue(color, 'Grn ');
  final double? blue = _numberValue(color, 'Bl  ');
  if (red == null || green == null || blue == null) {
    return null;
  }
  return PsdEffectColor(alpha: 255, red: red.clamp(0, 255).round(), green: green.clamp(0, 255).round(), blue: blue.clamp(0, 255).round());
}

/// Reads a gradient descriptor value.
PsdEffectGradient? _gradientValue(PsDescriptorValue? value) {
  if (value is! PsObjectValue) {
    return null;
  }
  final PsDescriptor gradient = value.value;
  final List<PsdGradientColorStop> colors = <PsdGradientColorStop>[];
  final List<PsdGradientOpacityStop> opacities = <PsdGradientOpacityStop>[];
  if (gradient.value('Clrs') case PsListValue(:final List<PsDescriptorValue> values)) {
    for (final PsDescriptorValue value in values) {
      if (value case PsObjectValue(:final PsDescriptor value)) {
        final PsdEffectColor? color = _colorValue(value.value('Clr '));
        if (color != null) {
          colors.add(
            PsdGradientColorStop(
              color: color,
              location: _numberValue(value, 'Lctn')?.round() ?? 0,
              midpoint: _numberValue(value, 'Mdpn')?.round() ?? 50,
            ),
          );
        }
      }
    }
  }
  if (gradient.value('Trns') case PsListValue(:final List<PsDescriptorValue> values)) {
    for (final PsDescriptorValue value in values) {
      if (value case PsObjectValue(:final PsDescriptor value)) {
        opacities.add(
          PsdGradientOpacityStop(
            opacity: _numberValue(value, 'Opct') ?? 100,
            location: _numberValue(value, 'Lctn')?.round() ?? 0,
            midpoint: _numberValue(value, 'Mdpn')?.round() ?? 50,
          ),
        );
      }
    }
  }
  return PsdEffectGradient(name: _stringValue(gradient, 'Nm  ') ?? '', colors: colors, opacities: opacities);
}

/// Reads a pattern descriptor value.
PsdEffectPattern? _patternValue(PsDescriptorValue? value) {
  if (value is! PsObjectValue) {
    return null;
  }
  return PsdEffectPattern(name: _stringValue(value.value, 'Nm  ') ?? '', id: _stringValue(value.value, 'Idnt') ?? '');
}

/// Reads a Unicode string property and removes its terminal NUL.
String? _stringValue(PsDescriptor descriptor, String key) => switch (descriptor.value(key)) {
  PsStringValue(:final String value) => value.endsWith('\u0000') ? value.substring(0, value.length - 1) : value,
  _ => null,
};

/// Creates an RGB action descriptor for [color].
PsDescriptor _colorDescriptor(PsdEffectColor color) => PsDescriptor(
  name: '\u0000',
  classId: 'RGBC',
  items: <PsDescriptorItem>[
    PsDescriptorItem(
      key: 'Rd  ',
      value: PsDoubleValue(value: color.red.toDouble()),
    ),
    PsDescriptorItem(
      key: 'Grn ',
      value: PsDoubleValue(value: color.green.toDouble()),
    ),
    PsDescriptorItem(
      key: 'Bl  ',
      value: PsDoubleValue(value: color.blue.toDouble()),
    ),
  ],
);

/// Creates Photoshop's default two-point linear contour descriptor.
PsDescriptor _linearContourDescriptor() => PsDescriptor(
  name: '\u0000',
  classId: 'ShpC',
  items: <PsDescriptorItem>[
    const PsDescriptorItem(
      key: 'Nm  ',
      value: PsStringValue(value: 'Linear\u0000'),
    ),
    PsDescriptorItem(
      key: 'Crv ',
      value: PsListValue(
        values: <PsDescriptorValue>[
          PsObjectValue(value: _curvePointDescriptor(0, 0)),
          PsObjectValue(value: _curvePointDescriptor(255, 255)),
        ],
      ),
    ),
  ],
);

/// Creates one point in a Photoshop contour curve.
PsDescriptor _curvePointDescriptor(double horizontal, double vertical) => PsDescriptor(
  name: '\u0000',
  classId: 'CrPt',
  items: <PsDescriptorItem>[
    PsDescriptorItem(
      key: 'Hrzn',
      value: PsDoubleValue(value: horizontal),
    ),
    PsDescriptorItem(
      key: 'Vrtc',
      value: PsDoubleValue(value: vertical),
    ),
  ],
);

/// Creates a two-dimensional Photoshop point descriptor.
PsDescriptor _pointDescriptor(double horizontal, double vertical, {String? unit}) => PsDescriptor(
  name: '\u0000',
  classId: 'Pnt ',
  items: <PsDescriptorItem>[
    PsDescriptorItem(
      key: 'Hrzn',
      value: unit == null ? PsDoubleValue(value: horizontal) : PsUnitFloatValue(unit: unit, value: horizontal),
    ),
    PsDescriptorItem(
      key: 'Vrtc',
      value: unit == null ? PsDoubleValue(value: vertical) : PsUnitFloatValue(unit: unit, value: vertical),
    ),
  ],
);

/// Creates an action descriptor for [gradient].
PsDescriptor _gradientDescriptor(PsdEffectGradient gradient) => PsDescriptor(
  name: '${gradient.name}\u0000',
  classId: 'Grdn',
  items: <PsDescriptorItem>[
    PsDescriptorItem(
      key: 'Nm  ',
      value: PsStringValue(value: '${gradient.name}\u0000'),
    ),
    const PsDescriptorItem(
      key: 'GrdF',
      value: PsEnumeratedValue(typeId: 'GrdF', value: 'CstS'),
    ),
    const PsDescriptorItem(key: 'Intr', value: PsDoubleValue(value: 4096)),
    PsDescriptorItem(
      key: 'Clrs',
      value: PsListValue(
        values: <PsDescriptorValue>[
          for (final PsdGradientColorStop stop in gradient.colors)
            PsObjectValue(
              value: PsDescriptor(
                name: '\u0000',
                classId: 'Clrt',
                items: <PsDescriptorItem>[
                  PsDescriptorItem(
                    key: 'Clr ',
                    value: PsObjectValue(value: _colorDescriptor(stop.color)),
                  ),
                  const PsDescriptorItem(
                    key: 'Type',
                    value: PsEnumeratedValue(typeId: 'Clry', value: 'UsrS'),
                  ),
                  PsDescriptorItem(
                    key: 'Lctn',
                    value: PsIntegerValue(value: stop.location),
                  ),
                  PsDescriptorItem(
                    key: 'Mdpn',
                    value: PsIntegerValue(value: stop.midpoint),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
    PsDescriptorItem(
      key: 'Trns',
      value: PsListValue(
        values: <PsDescriptorValue>[
          for (final PsdGradientOpacityStop stop in gradient.opacities)
            PsObjectValue(
              value: PsDescriptor(
                name: '\u0000',
                classId: 'TrnS',
                items: <PsDescriptorItem>[
                  PsDescriptorItem(
                    key: 'Opct',
                    value: PsUnitFloatValue(unit: '#Prc', value: stop.opacity),
                  ),
                  PsDescriptorItem(
                    key: 'Lctn',
                    value: PsIntegerValue(value: stop.location),
                  ),
                  PsDescriptorItem(
                    key: 'Mdpn',
                    value: PsIntegerValue(value: stop.midpoint),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  ],
);

/// Creates an action descriptor for [pattern].
PsDescriptor _patternDescriptor(PsdEffectPattern pattern) => PsDescriptor(
  name: '\u0000',
  classId: 'Ptrn',
  items: <PsDescriptorItem>[
    PsDescriptorItem(
      key: 'Nm  ',
      value: PsStringValue(value: '${pattern.name}\u0000'),
    ),
    PsDescriptorItem(
      key: 'Idnt',
      value: PsStringValue(value: '${pattern.id}\u0000'),
    ),
  ],
);

/// Returns a simple opaque two-stop gradient ending in [color].
PsdEffectGradient _defaultGradient(PsdEffectColor color) => PsdEffectGradient(
  colors: <PsdGradientColorStop>[
    const PsdGradientColorStop(color: PsdEffectColor.black, location: 0),
    PsdGradientColorStop(color: color, location: 4096),
  ],
  opacities: const <PsdGradientOpacityStop>[
    PsdGradientOpacityStop(opacity: 100, location: 0),
    PsdGradientOpacityStop(opacity: 100, location: 4096),
  ],
);

/// Maps a root descriptor [key] to its effect family.
PsdLayerEffectType? _effectTypeForRootKey(String key) {
  for (final PsdLayerEffectType type in PsdLayerEffectType.values) {
    if (type != PsdLayerEffectType.unknown && (key == _effectRootKey(type) || key == _effectMultiRootKey(type))) {
      return type;
    }
  }
  return null;
}

/// Returns the singular root key for [type].
String _effectRootKey(PsdLayerEffectType type) => switch (type) {
  PsdLayerEffectType.dropShadow => 'DrSh',
  PsdLayerEffectType.innerShadow => 'IrSh',
  PsdLayerEffectType.outerGlow => 'OrGl',
  PsdLayerEffectType.innerGlow => 'IrGl',
  PsdLayerEffectType.bevelEmboss => 'ebbl',
  PsdLayerEffectType.satin => 'ChFX',
  PsdLayerEffectType.colorOverlay => 'SoFi',
  PsdLayerEffectType.gradientOverlay => 'GrFl',
  PsdLayerEffectType.patternOverlay => 'patternFill',
  PsdLayerEffectType.stroke => 'FrFX',
  PsdLayerEffectType.unknown => 'unknown',
};

/// Returns the repeated-effect root key for [type].
String _effectMultiRootKey(PsdLayerEffectType type) => switch (type) {
  PsdLayerEffectType.dropShadow => 'dropShadowMulti',
  PsdLayerEffectType.innerShadow => 'innerShadowMulti',
  PsdLayerEffectType.outerGlow => 'outerGlowMulti',
  PsdLayerEffectType.innerGlow => 'innerGlowMulti',
  PsdLayerEffectType.bevelEmboss => 'bevelEmbossMulti',
  PsdLayerEffectType.satin => 'satinMulti',
  PsdLayerEffectType.colorOverlay => 'solidFillMulti',
  PsdLayerEffectType.gradientOverlay => 'gradientFillMulti',
  PsdLayerEffectType.patternOverlay => 'patternFillMulti',
  PsdLayerEffectType.stroke => 'frameFXMulti',
  PsdLayerEffectType.unknown => 'unknownMulti',
};

/// Returns the descriptor class identifier for [type].
String _effectClassId(PsdLayerEffectType type) => switch (type) {
  PsdLayerEffectType.dropShadow => 'DrSh',
  PsdLayerEffectType.innerShadow => 'IrSh',
  PsdLayerEffectType.outerGlow => 'OrGl',
  PsdLayerEffectType.innerGlow => 'IrGl',
  PsdLayerEffectType.bevelEmboss => 'ebbl',
  PsdLayerEffectType.satin => 'ChFX',
  PsdLayerEffectType.colorOverlay => 'SoFi',
  PsdLayerEffectType.gradientOverlay => 'GrFl',
  PsdLayerEffectType.patternOverlay => 'patternFill',
  PsdLayerEffectType.stroke => 'FrFX',
  PsdLayerEffectType.unknown => 'null',
};

/// Returns Photoshop's enumeration identifier for [position].
String _strokePositionId(PsdStrokePosition position) => switch (position) {
  PsdStrokePosition.inside => 'InsF',
  PsdStrokePosition.center => 'CtrF',
  PsdStrokePosition.outside => 'OutF',
};

/// Returns Photoshop's enumeration identifier for [style].
String _gradientStyleId(PsdGradientStyle style) => switch (style) {
  PsdGradientStyle.linear => 'Lnr ',
  PsdGradientStyle.radial => 'Rdl ',
  PsdGradientStyle.angle => 'Angl',
  PsdGradientStyle.reflected => 'Rflc',
  PsdGradientStyle.diamond => 'Dmnd',
};
