part of '../effects.dart';

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

  /// Primary effect color in sRGB, when the effect has a convertible one.
  PsdEffectColor? get color => _rgb(view.color) ?? _rgb(view.highlightColor);

  /// Blur or stroke size in pixels, when applicable.
  double? get size => descriptor.scalarValue(type == PsdLayerEffectType.stroke ? 'Sz  ' : 'blur');

  /// Lighting or gradient angle in degrees, when applicable.
  double? get angle => descriptor.scalarValue(descriptor.value('lagl') == null ? 'Angl' : 'lagl');

  /// Shadow distance in pixels, when applicable.
  double? get distance => descriptor.scalarValue('Dstn');

  /// Shadow spread or glow choke, as a percentage of the effect size.
  ///
  /// Photoshop tags the value with a pixel unit, but its dialog and renderer
  /// treat it as a percentage.
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
