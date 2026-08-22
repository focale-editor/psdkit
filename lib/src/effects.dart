import 'dart:typed_data';

import 'package:psdkit/src/binary.dart';
import 'package:psdkit/src/descriptor.dart';

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
  final PsdDescriptor descriptor;

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
    final List<PsdDescriptorItem> items = <PsdDescriptorItem>[
      PsdDescriptorItem(key: 'enab', value: PsdBooleanValue(enabled)),
      PsdDescriptorItem(key: 'present', value: PsdBooleanValue(true)),
      PsdDescriptorItem(key: 'showInDialog', value: PsdBooleanValue(true)),
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
      descriptor: PsdDescriptor(name: '\u0000', classId: _effectClassId(type), items: items),
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
  PsdLayerEffect withProperty(String key, PsdDescriptorValue value) => PsdLayerEffect(type: type, descriptor: descriptor.withValue(key, value));

  /// Returns a copy whose enabled state is [value].
  PsdLayerEffect withEnabled(bool value) => withProperty('enab', PsdBooleanValue(value));

  /// Returns a copy whose opacity percentage is [value].
  PsdLayerEffect withOpacity(double value) => withProperty(
    type == PsdLayerEffectType.bevelEmboss ? 'hglO' : 'Opct',
    PsdUnitFloatValue(unit: '#Prc', value: value),
  );

  /// Returns a copy whose primary color is [value].
  PsdLayerEffect withColor(PsdEffectColor value) => withProperty(
    type == PsdLayerEffectType.bevelEmboss ? 'hglC' : 'Clr ',
    PsdObjectValue(_colorDescriptor(value)),
  );
}

/// A complete editable modern or imported legacy layer-effects record.
final class PsdLayerEffects {
  /// Effects record version, normally zero.
  final int version;

  /// Action-descriptor version, normally 16.
  final int descriptorVersion;

  /// Complete modern effects descriptor.
  final PsdDescriptor descriptor;

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
      descriptor: PsdDescriptor(
        name: '\u0000',
        classId: 'null',
        items: <PsdDescriptorItem>[
          PsdDescriptorItem(
            key: 'Scl ',
            value: PsdUnitFloatValue(unit: '#Prc', value: scale),
          ),
          PsdDescriptorItem(key: 'masterFXSwitch', value: PsdBooleanValue(enabled)),
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
    final List<PsdDescriptorItem> items = <PsdDescriptorItem>[
      for (final PsdDescriptorItem item in descriptor.items)
        if (!_effectRootKeys.contains(item.key)) item,
      ..._writeEffectItems(effects),
    ];
    return PsdLayerEffects(
      version: version,
      descriptorVersion: descriptorVersion,
      descriptor: PsdDescriptor(name: descriptor.name, classId: descriptor.classId, items: items),
      trailingData: blockKey == 'lrFX' ? null : trailingData,
    );
  }

  /// Returns a copy whose global enabled state is [value].
  PsdLayerEffects withEnabled(bool value) => PsdLayerEffects(
    version: version,
    descriptorVersion: descriptorVersion,
    descriptor: descriptor.withValue('masterFXSwitch', PsdBooleanValue(value)),
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
    final PsdBinaryReader reader = PsdBinaryReader(bytes);
    final int version = reader.readUint32();
    final int descriptorVersion = reader.readUint32();
    final ({PsdDescriptor descriptor, int bytesRead}) decoded = PsdDescriptorCodec.decodePrefix(Uint8List.sublistView(bytes, reader.offset));
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
    return (PsdBinaryWriter()
          ..writeUint32(effects.version)
          ..writeUint32(effects.descriptorVersion)
          ..writeBytes(PsdDescriptorCodec.encode(effects.descriptor))
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
List<PsdLayerEffect> _readEffects(PsdDescriptor descriptor) {
  final List<PsdLayerEffect> result = <PsdLayerEffect>[];
  for (final PsdDescriptorItem item in descriptor.items) {
    final PsdLayerEffectType? type = _effectTypeForRootKey(item.key);
    if (type == null) {
      continue;
    }
    switch (item.value) {
      case PsdObjectValue(:final PsdDescriptor value):
        result.add(PsdLayerEffect(type: type, descriptor: value));
      case PsdListValue(:final List<PsdDescriptorValue> values):
        for (final PsdDescriptorValue value in values) {
          if (value case PsdObjectValue(:final PsdDescriptor value)) {
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
List<PsdDescriptorItem> _writeEffectItems(List<PsdLayerEffect> effects) {
  final List<PsdDescriptorItem> result = <PsdDescriptorItem>[];
  for (final PsdLayerEffectType type in PsdLayerEffectType.values) {
    if (type == PsdLayerEffectType.unknown) {
      continue;
    }
    final List<PsdLayerEffect> matches = effects.where((effect) => effect.type == type).toList();
    if (matches.isEmpty) {
      continue;
    }
    if (matches.length == 1) {
      result.add(PsdDescriptorItem(key: _effectRootKey(type), value: PsdObjectValue(matches.single.descriptor)));
    } else {
      result.add(
        PsdDescriptorItem(
          key: _effectMultiRootKey(type),
          value: PsdListValue(<PsdDescriptorValue>[for (final PsdLayerEffect effect in matches) PsdObjectValue(effect.descriptor)]),
        ),
      );
    }
  }
  return result;
}

/// Adds properties required by the selected effect [type].
void _appendEffectProperties(
  List<PsdDescriptorItem> items, {
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
        PsdDescriptorItem(
          key: 'Md  ',
          value: PsdEnumeratedValue(typeId: 'BlnM', value: blendMode),
        ),
      )
      ..add(
        PsdDescriptorItem(
          key: 'Opct',
          value: PsdUnitFloatValue(unit: '#Prc', value: opacity),
        ),
      );
  }
  switch (type) {
    case PsdLayerEffectType.dropShadow || PsdLayerEffectType.innerShadow:
      items
        ..add(PsdDescriptorItem(key: 'Clr ', value: PsdObjectValue(_colorDescriptor(color))))
        ..add(PsdDescriptorItem(key: 'uglg', value: PsdBooleanValue(useGlobalAngle)))
        ..add(
          PsdDescriptorItem(
            key: 'lagl',
            value: PsdUnitFloatValue(unit: '#Ang', value: angle),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'Dstn',
            value: PsdUnitFloatValue(unit: '#Pxl', value: distance),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'Ckmt',
            value: PsdUnitFloatValue(unit: '#Pxl', value: spread),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'blur',
            value: PsdUnitFloatValue(unit: '#Pxl', value: size),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'Nose',
            value: PsdUnitFloatValue(unit: '#Prc', value: noise),
          ),
        )
        ..add(PsdDescriptorItem(key: 'AntA', value: PsdBooleanValue(false)))
        ..add(PsdDescriptorItem(key: 'TrnS', value: PsdObjectValue(_linearContourDescriptor())))
        ..add(PsdDescriptorItem(key: 'layerConceals', value: PsdBooleanValue(true)));
    case PsdLayerEffectType.outerGlow || PsdLayerEffectType.innerGlow:
      items
        ..add(PsdDescriptorItem(key: 'Clr ', value: PsdObjectValue(_colorDescriptor(color))))
        ..add(
          PsdDescriptorItem(
            key: 'GlwT',
            value: PsdEnumeratedValue(typeId: 'BETE', value: 'SfBL'),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'Ckmt',
            value: PsdUnitFloatValue(unit: '#Pxl', value: spread),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'blur',
            value: PsdUnitFloatValue(unit: '#Pxl', value: size),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'Nose',
            value: PsdUnitFloatValue(unit: '#Prc', value: noise),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'ShdN',
            value: PsdUnitFloatValue(unit: '#Prc', value: 0),
          ),
        )
        ..add(PsdDescriptorItem(key: 'AntA', value: PsdBooleanValue(false)))
        ..add(PsdDescriptorItem(key: 'TrnS', value: PsdObjectValue(_linearContourDescriptor())))
        ..add(
          PsdDescriptorItem(
            key: 'Inpr',
            value: PsdUnitFloatValue(unit: '#Prc', value: 50),
          ),
        );
      if (type == PsdLayerEffectType.innerGlow) {
        items.add(
          PsdDescriptorItem(
            key: 'glwS',
            value: PsdEnumeratedValue(typeId: 'IGSr', value: 'SrcE'),
          ),
        );
      }
    case PsdLayerEffectType.colorOverlay:
      items.add(PsdDescriptorItem(key: 'Clr ', value: PsdObjectValue(_colorDescriptor(color))));
    case PsdLayerEffectType.gradientOverlay:
      items
        ..add(PsdDescriptorItem(key: 'Grad', value: PsdObjectValue(_gradientDescriptor(gradient ?? _defaultGradient(color)))))
        ..add(
          PsdDescriptorItem(
            key: 'Angl',
            value: PsdUnitFloatValue(unit: '#Ang', value: angle),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'Type',
            value: PsdEnumeratedValue(typeId: 'GrdT', value: _gradientStyleId(gradientStyle)),
          ),
        )
        ..add(PsdDescriptorItem(key: 'Rvrs', value: PsdBooleanValue(reverse)))
        ..add(PsdDescriptorItem(key: 'Dthr', value: PsdBooleanValue(dither)))
        ..add(PsdDescriptorItem(key: 'Algn', value: PsdBooleanValue(aligned)))
        ..add(
          PsdDescriptorItem(
            key: 'Scl ',
            value: PsdUnitFloatValue(unit: '#Prc', value: scale),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'Ofst',
            value: PsdObjectValue(_pointDescriptor(offsetX, offsetY, unit: '#Prc')),
          ),
        );
    case PsdLayerEffectType.patternOverlay:
      items
        ..add(
          PsdDescriptorItem(
            key: 'Ptrn',
            value: PsdObjectValue(_patternDescriptor(pattern ?? const PsdEffectPattern(name: '', id: ''))),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'Scl ',
            value: PsdUnitFloatValue(unit: '#Prc', value: scale),
          ),
        )
        ..add(PsdDescriptorItem(key: 'Algn', value: PsdBooleanValue(aligned)))
        ..add(PsdDescriptorItem(key: 'phase', value: PsdObjectValue(_pointDescriptor(offsetX, offsetY))));
    case PsdLayerEffectType.stroke:
      final String fillType = gradient != null ? 'GrFl' : (pattern != null ? 'Ptrn' : 'SClr');
      items
        ..add(
          PsdDescriptorItem(
            key: 'Styl',
            value: PsdEnumeratedValue(typeId: 'FStl', value: _strokePositionId(strokePosition)),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'PntT',
            value: PsdEnumeratedValue(typeId: 'FrFl', value: fillType),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'Sz  ',
            value: PsdUnitFloatValue(unit: '#Pxl', value: size),
          ),
        )
        ..add(PsdDescriptorItem(key: 'Clr ', value: PsdObjectValue(_colorDescriptor(color))))
        ..add(PsdDescriptorItem(key: 'overprint', value: PsdBooleanValue(false)));
      if (gradient != null) {
        items.add(PsdDescriptorItem(key: 'Grad', value: PsdObjectValue(_gradientDescriptor(gradient))));
      } else if (pattern != null) {
        items.add(PsdDescriptorItem(key: 'Ptrn', value: PsdObjectValue(_patternDescriptor(pattern))));
      }
    case PsdLayerEffectType.satin:
      items
        ..add(PsdDescriptorItem(key: 'Clr ', value: PsdObjectValue(_colorDescriptor(color))))
        ..add(
          PsdDescriptorItem(
            key: 'lagl',
            value: PsdUnitFloatValue(unit: '#Ang', value: angle),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'Dstn',
            value: PsdUnitFloatValue(unit: '#Pxl', value: distance),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'blur',
            value: PsdUnitFloatValue(unit: '#Pxl', value: size),
          ),
        )
        ..add(PsdDescriptorItem(key: 'AntA', value: PsdBooleanValue(true)))
        ..add(PsdDescriptorItem(key: 'Invr', value: PsdBooleanValue(false)))
        ..add(PsdDescriptorItem(key: 'MpgS', value: PsdObjectValue(_linearContourDescriptor())));
    case PsdLayerEffectType.bevelEmboss:
      items
        ..add(
          PsdDescriptorItem(
            key: 'hglM',
            value: PsdEnumeratedValue(typeId: 'BlnM', value: 'Scrn'),
          ),
        )
        ..add(PsdDescriptorItem(key: 'hglC', value: PsdObjectValue(_colorDescriptor(color))))
        ..add(
          PsdDescriptorItem(
            key: 'hglO',
            value: PsdUnitFloatValue(unit: '#Prc', value: opacity),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'sdwM',
            value: PsdEnumeratedValue(typeId: 'BlnM', value: 'Mltp'),
          ),
        )
        ..add(PsdDescriptorItem(key: 'sdwC', value: PsdObjectValue(_colorDescriptor(PsdEffectColor.black))))
        ..add(
          PsdDescriptorItem(
            key: 'sdwO',
            value: PsdUnitFloatValue(unit: '#Prc', value: opacity),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'bvlT',
            value: PsdEnumeratedValue(typeId: 'bvlT', value: 'SfBL'),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'bvlS',
            value: PsdEnumeratedValue(typeId: 'BESl', value: 'InrB'),
          ),
        )
        ..add(PsdDescriptorItem(key: 'uglg', value: PsdBooleanValue(useGlobalAngle)))
        ..add(
          PsdDescriptorItem(
            key: 'lagl',
            value: PsdUnitFloatValue(unit: '#Ang', value: angle),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'Lald',
            value: PsdUnitFloatValue(unit: '#Ang', value: 30),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'srgR',
            value: PsdUnitFloatValue(unit: '#Prc', value: 100),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'blur',
            value: PsdUnitFloatValue(unit: '#Pxl', value: size),
          ),
        )
        ..add(
          PsdDescriptorItem(
            key: 'bvlD',
            value: PsdEnumeratedValue(typeId: 'BESs', value: 'In  '),
          ),
        )
        ..add(PsdDescriptorItem(key: 'TrnS', value: PsdObjectValue(_linearContourDescriptor())))
        ..add(PsdDescriptorItem(key: 'antialiasGloss', value: PsdBooleanValue(false)))
        ..add(
          PsdDescriptorItem(
            key: 'Sftn',
            value: PsdUnitFloatValue(unit: '#Pxl', value: 0),
          ),
        )
        ..add(PsdDescriptorItem(key: 'useShape', value: PsdBooleanValue(false)))
        ..add(PsdDescriptorItem(key: 'useTexture', value: PsdBooleanValue(false)));
    case PsdLayerEffectType.unknown:
      break;
  }
}

/// Builds a modern semantic descriptor from a historical `lrFX` payload.
PsdLayerEffects _decodeLegacyEffects(Uint8List bytes) {
  final PsdBinaryReader reader = PsdBinaryReader(bytes);
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
    final PsdBinaryReader effect = reader.readReader(length);
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
PsdLayerEffect? _decodeLegacyEffect(String key, PsdBinaryReader reader) => switch (key) {
  'dsdw' => _decodeLegacyShadow(reader, PsdLayerEffectType.dropShadow),
  'isdw' => _decodeLegacyShadow(reader, PsdLayerEffectType.innerShadow),
  'oglw' => _decodeLegacyGlow(reader, PsdLayerEffectType.outerGlow),
  'iglw' => _decodeLegacyGlow(reader, PsdLayerEffectType.innerGlow),
  'sofi' => _decodeLegacySolidFill(reader),
  'bevl' => _decodeLegacyBevel(reader),
  _ => null,
};

/// Decodes a historical outer or inner shadow.
PsdLayerEffect _decodeLegacyShadow(PsdBinaryReader reader, PsdLayerEffectType type) {
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
PsdLayerEffect _decodeLegacyGlow(PsdBinaryReader reader, PsdLayerEffectType type) {
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
PsdLayerEffect _decodeLegacySolidFill(PsdBinaryReader reader) {
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
PsdLayerEffect _decodeLegacyBevel(PsdBinaryReader reader) {
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
PsdEffectColor _readLegacyColor(PsdBinaryReader reader, {PsdEffectColor fallback = PsdEffectColor.black}) {
  final int space = reader.readUint16();
  final List<int> components = <int>[for (int index = 0; index < 4; index++) reader.readUint16()];
  if (space != 0) {
    return fallback;
  }
  return PsdEffectColor(alpha: 255, red: (components[0] / 257).round(), green: (components[1] / 257).round(), blue: (components[2] / 257).round());
}

/// Reads a Boolean property from [descriptor].
bool? _boolValue(PsdDescriptor descriptor, String key) => switch (descriptor.value(key)) {
  PsdBooleanValue(:final bool value) => value,
  _ => null,
};

/// Reads a numeric property from [descriptor].
double? _numberValue(PsdDescriptor descriptor, String key) => switch (descriptor.value(key)) {
  PsdUnitFloatValue(:final double value) => value,
  PsdDoubleValue(:final double value) => value,
  PsdIntegerValue(:final int value) => value.toDouble(),
  _ => null,
};

/// Reads an enumeration identifier from [descriptor].
String? _enumValue(PsdDescriptor descriptor, String key) => switch (descriptor.value(key)) {
  PsdEnumeratedValue(:final String value) => value,
  _ => null,
};

/// Reads an RGB descriptor value.
PsdEffectColor? _colorValue(PsdDescriptorValue? value) {
  if (value is! PsdObjectValue) {
    return null;
  }
  final PsdDescriptor color = value.value;
  final double? red = _numberValue(color, 'Rd  ');
  final double? green = _numberValue(color, 'Grn ');
  final double? blue = _numberValue(color, 'Bl  ');
  if (red == null || green == null || blue == null) {
    return null;
  }
  return PsdEffectColor(alpha: 255, red: red.clamp(0, 255).round(), green: green.clamp(0, 255).round(), blue: blue.clamp(0, 255).round());
}

/// Reads a gradient descriptor value.
PsdEffectGradient? _gradientValue(PsdDescriptorValue? value) {
  if (value is! PsdObjectValue) {
    return null;
  }
  final PsdDescriptor gradient = value.value;
  final List<PsdGradientColorStop> colors = <PsdGradientColorStop>[];
  final List<PsdGradientOpacityStop> opacities = <PsdGradientOpacityStop>[];
  if (gradient.value('Clrs') case PsdListValue(:final List<PsdDescriptorValue> values)) {
    for (final PsdDescriptorValue value in values) {
      if (value case PsdObjectValue(:final PsdDescriptor value)) {
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
  if (gradient.value('Trns') case PsdListValue(:final List<PsdDescriptorValue> values)) {
    for (final PsdDescriptorValue value in values) {
      if (value case PsdObjectValue(:final PsdDescriptor value)) {
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
PsdEffectPattern? _patternValue(PsdDescriptorValue? value) {
  if (value is! PsdObjectValue) {
    return null;
  }
  return PsdEffectPattern(name: _stringValue(value.value, 'Nm  ') ?? '', id: _stringValue(value.value, 'Idnt') ?? '');
}

/// Reads a Unicode string property and removes its terminal NUL.
String? _stringValue(PsdDescriptor descriptor, String key) => switch (descriptor.value(key)) {
  PsdStringValue(:final String value) => value.endsWith('\u0000') ? value.substring(0, value.length - 1) : value,
  _ => null,
};

/// Creates an RGB action descriptor for [color].
PsdDescriptor _colorDescriptor(PsdEffectColor color) => PsdDescriptor(
  name: '\u0000',
  classId: 'RGBC',
  items: <PsdDescriptorItem>[
    PsdDescriptorItem(key: 'Rd  ', value: PsdDoubleValue(color.red.toDouble())),
    PsdDescriptorItem(key: 'Grn ', value: PsdDoubleValue(color.green.toDouble())),
    PsdDescriptorItem(key: 'Bl  ', value: PsdDoubleValue(color.blue.toDouble())),
  ],
);

/// Creates Photoshop's default two-point linear contour descriptor.
PsdDescriptor _linearContourDescriptor() => PsdDescriptor(
  name: '\u0000',
  classId: 'ShpC',
  items: <PsdDescriptorItem>[
    PsdDescriptorItem(key: 'Nm  ', value: PsdStringValue('Linear\u0000')),
    PsdDescriptorItem(
      key: 'Crv ',
      value: PsdListValue(<PsdDescriptorValue>[
        PsdObjectValue(_curvePointDescriptor(0, 0)),
        PsdObjectValue(_curvePointDescriptor(255, 255)),
      ]),
    ),
  ],
);

/// Creates one point in a Photoshop contour curve.
PsdDescriptor _curvePointDescriptor(double horizontal, double vertical) => PsdDescriptor(
  name: '\u0000',
  classId: 'CrPt',
  items: <PsdDescriptorItem>[
    PsdDescriptorItem(key: 'Hrzn', value: PsdDoubleValue(horizontal)),
    PsdDescriptorItem(key: 'Vrtc', value: PsdDoubleValue(vertical)),
  ],
);

/// Creates a two-dimensional Photoshop point descriptor.
PsdDescriptor _pointDescriptor(double horizontal, double vertical, {String? unit}) => PsdDescriptor(
  name: '\u0000',
  classId: 'Pnt ',
  items: <PsdDescriptorItem>[
    PsdDescriptorItem(
      key: 'Hrzn',
      value: unit == null ? PsdDoubleValue(horizontal) : PsdUnitFloatValue(unit: unit, value: horizontal),
    ),
    PsdDescriptorItem(
      key: 'Vrtc',
      value: unit == null ? PsdDoubleValue(vertical) : PsdUnitFloatValue(unit: unit, value: vertical),
    ),
  ],
);

/// Creates an action descriptor for [gradient].
PsdDescriptor _gradientDescriptor(PsdEffectGradient gradient) => PsdDescriptor(
  name: '${gradient.name}\u0000',
  classId: 'Grdn',
  items: <PsdDescriptorItem>[
    PsdDescriptorItem(key: 'Nm  ', value: PsdStringValue('${gradient.name}\u0000')),
    PsdDescriptorItem(
      key: 'GrdF',
      value: PsdEnumeratedValue(typeId: 'GrdF', value: 'CstS'),
    ),
    PsdDescriptorItem(key: 'Intr', value: PsdDoubleValue(4096)),
    PsdDescriptorItem(
      key: 'Clrs',
      value: PsdListValue(<PsdDescriptorValue>[
        for (final PsdGradientColorStop stop in gradient.colors)
          PsdObjectValue(
            PsdDescriptor(
              name: '\u0000',
              classId: 'Clrt',
              items: <PsdDescriptorItem>[
                PsdDescriptorItem(key: 'Clr ', value: PsdObjectValue(_colorDescriptor(stop.color))),
                PsdDescriptorItem(
                  key: 'Type',
                  value: PsdEnumeratedValue(typeId: 'Clry', value: 'UsrS'),
                ),
                PsdDescriptorItem(key: 'Lctn', value: PsdIntegerValue(stop.location)),
                PsdDescriptorItem(key: 'Mdpn', value: PsdIntegerValue(stop.midpoint)),
              ],
            ),
          ),
      ]),
    ),
    PsdDescriptorItem(
      key: 'Trns',
      value: PsdListValue(<PsdDescriptorValue>[
        for (final PsdGradientOpacityStop stop in gradient.opacities)
          PsdObjectValue(
            PsdDescriptor(
              name: '\u0000',
              classId: 'TrnS',
              items: <PsdDescriptorItem>[
                PsdDescriptorItem(
                  key: 'Opct',
                  value: PsdUnitFloatValue(unit: '#Prc', value: stop.opacity),
                ),
                PsdDescriptorItem(key: 'Lctn', value: PsdIntegerValue(stop.location)),
                PsdDescriptorItem(key: 'Mdpn', value: PsdIntegerValue(stop.midpoint)),
              ],
            ),
          ),
      ]),
    ),
  ],
);

/// Creates an action descriptor for [pattern].
PsdDescriptor _patternDescriptor(PsdEffectPattern pattern) => PsdDescriptor(
  name: '\u0000',
  classId: 'Ptrn',
  items: <PsdDescriptorItem>[
    PsdDescriptorItem(key: 'Nm  ', value: PsdStringValue('${pattern.name}\u0000')),
    PsdDescriptorItem(key: 'Idnt', value: PsdStringValue('${pattern.id}\u0000')),
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
