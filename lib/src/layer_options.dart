import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:psdkit/src/model.dart';

/// Looks up the last tagged block stored under a key.
typedef PsdTaggedBlockLookup = PsdTaggedBlock? Function(String key);

/// How deeply a layer punches through the layers below it.
enum PsdKnockout {
  /// Blends normally with the layers below.
  none,

  /// Reveals the bottom of the enclosing group.
  shallow,

  /// Reveals the document background.
  deep,
}

/// Photoshop's color label shown in the Layers panel.
enum PsdSheetColor {
  /// No label.
  none(0),

  /// Red label.
  red(1),

  /// Orange label.
  orange(2),

  /// Yellow label.
  yellow(3),

  /// Green label.
  green(4),

  /// Blue label.
  blue(5),

  /// Violet label.
  violet(6),

  /// Gray label.
  gray(7);

  /// Index stored in the `lclr` block.
  final int code;

  /// Creates a label stored as [code].
  const PsdSheetColor(this.code);

  /// Returns the label stored as [code], or `null` for a newer label.
  static PsdSheetColor? fromCode(int code) {
    for (final PsdSheetColor color in values) {
      if (color.code == code) {
        return color;
      }
    }
    return null;
  }
}

/// Advanced blending options stored in individual layer tagged blocks.
///
/// Absent blocks decode to Photoshop's defaults. A block whose payload cannot
/// be interpreted also decodes to the default value, and its key is listed in
/// [malformedKeys] so callers can decide whether the result is trustworthy.
final class PsdLayerBlendingOptions {
  /// Tagged-block keys owned by these options.
  static const Set<String> blockKeys = {'iOpa', 'clbl', 'infx', 'knko', 'tsly', 'lmgm', 'vmgm', 'brst'};

  /// Fill opacity from 0 through 255, applied before layer effects.
  final int fillOpacity;

  /// Whether clipped layers are blended as a group (`clbl`).
  final bool blendClippedLayers;

  /// Whether interior effects are blended with the layer (`infx`).
  final bool blendInteriorEffects;

  /// Knockout depth (`knko`).
  final PsdKnockout knockout;

  /// Whether layer transparency shapes the layer and its effects (`tsly`).
  final bool transparencyShapesLayer;

  /// Whether the raster mask also hides effects (`lmgm`), when stored.
  ///
  /// Without the block, Photoshop derives this from the raster-mask flags.
  final bool? layerMaskHidesEffects;

  /// Whether the vector mask also hides effects (`vmgm`), when stored.
  ///
  /// Without the block, Photoshop derives this from the vector-mask link flag.
  final bool? vectorMaskHidesEffects;

  /// Zero-based color channels the layer does not blend into (`brst`).
  final List<int> restrictedChannels;

  /// Keys of present blocks that could not be interpreted.
  final Set<String> malformedKeys;

  /// Creates blending options, defaulting to Photoshop's behavior.
  PsdLayerBlendingOptions({
    this.fillOpacity = 255,
    this.blendClippedLayers = true,
    this.blendInteriorEffects = false,
    this.knockout = PsdKnockout.none,
    this.transparencyShapesLayer = true,
    this.layerMaskHidesEffects,
    this.vectorMaskHidesEffects,
    List<int> restrictedChannels = const [],
    Set<String> malformedKeys = const {},
  }) : restrictedChannels = List<int>.unmodifiable(restrictedChannels),
       malformedKeys = Set<String>.unmodifiable(malformedKeys);

  /// Decodes the blending blocks returned by [lookup].
  factory PsdLayerBlendingOptions.decode(PsdTaggedBlockLookup lookup) {
    final Set<String> malformedKeys = {};
    int? byteAt(String key, int maximum) {
      final PsdTaggedBlock? block = lookup(key);
      if (block == null) {
        return null;
      }
      final Uint8List data = block.data;
      if (data.isEmpty || data.first > maximum || data.skip(1).any((value) => value != 0)) {
        malformedKeys.add(key);
        return null;
      }
      return data.first;
    }

    bool? booleanAt(String key) => switch (byteAt(key, 1)) {
      null => null,
      final int value => value != 0,
    };

    final int? knockout = byteAt('knko', PsdKnockout.values.length - 1);
    return PsdLayerBlendingOptions(
      fillOpacity: byteAt('iOpa', 255) ?? 255,
      blendClippedLayers: booleanAt('clbl') ?? true,
      blendInteriorEffects: booleanAt('infx') ?? false,
      knockout: knockout == null ? PsdKnockout.none : PsdKnockout.values[knockout],
      transparencyShapesLayer: booleanAt('tsly') ?? true,
      layerMaskHidesEffects: booleanAt('lmgm'),
      vectorMaskHidesEffects: booleanAt('vmgm'),
      restrictedChannels: _restrictedChannels(lookup('brst'), malformedKeys),
      malformedKeys: malformedKeys,
    );
  }

  /// Whether at least one present block could not be interpreted.
  bool get isMalformed => malformedKeys.isNotEmpty;

  /// Encodes these options as canonical four-byte-aligned tagged blocks.
  ///
  /// Like Photoshop, this always writes `clbl`, `infx`, and `knko`, but omits
  /// `iOpa` and `tsly` at their defaults, mask blocks whose value is `null`,
  /// and `brst` when no channel is restricted.
  List<PsdTaggedBlock> toBlocks() {
    if (fillOpacity < 0 || fillOpacity > 255) {
      throw PsWriteException(message: 'Fill opacity $fillOpacity must be from 0 through 255');
    }
    final bool? layerMask = layerMaskHidesEffects;
    final bool? vectorMask = vectorMaskHidesEffects;
    return [
      if (fillOpacity != 255) _byteBlock('iOpa', fillOpacity),
      _byteBlock('clbl', blendClippedLayers ? 1 : 0),
      _byteBlock('infx', blendInteriorEffects ? 1 : 0),
      _byteBlock('knko', knockout.index),
      if (!transparencyShapesLayer) _byteBlock('tsly', 0),
      if (layerMask != null) _byteBlock('lmgm', layerMask ? 1 : 0),
      if (vectorMask != null) _byteBlock('vmgm', vectorMask ? 1 : 0),
      if (restrictedChannels.isNotEmpty) _restrictedChannelsBlock(restrictedChannels),
    ];
  }

  /// Decodes the big-endian channel indices stored in a `brst` [block].
  static List<int> _restrictedChannels(PsdTaggedBlock? block, Set<String> malformedKeys) {
    if (block == null) {
      return const [];
    }
    if (block.data.length % 4 != 0) {
      malformedKeys.add(block.key);
      return const [];
    }
    final ByteData view = ByteData.sublistView(block.data);
    return [for (int offset = 0; offset < block.data.length; offset += 4) view.getInt32(offset)];
  }

  /// Encodes [channels] as a `brst` block.
  static PsdTaggedBlock _restrictedChannelsBlock(List<int> channels) {
    final ByteData data = ByteData(channels.length * 4);
    for (int index = 0; index < channels.length; index++) {
      data.setInt32(index * 4, channels[index]);
    }
    return PsdTaggedBlock(key: 'brst', data: data.buffer.asUint8List());
  }

  /// Encodes one byte followed by Photoshop's three padding bytes.
  static PsdTaggedBlock _byteBlock(String key, int value) => PsdTaggedBlock(key: key, data: Uint8List(4)..[0] = value);
}

/// Editing locks stored in the `lspf` block.
///
/// Photoshop also locks transparency through bit 0 of the layer-record flags;
/// [PsdLayer.protection] merges both sources.
final class PsdLayerProtection {
  /// Bit locking transparent pixels.
  static const int transparencyBit = 0x01;

  /// Bit locking image pixels.
  static const int pixelsBit = 0x02;

  /// Bit locking the layer position.
  static const int positionBit = 0x04;

  /// Bit preventing automatic nesting into or out of artboards.
  static const int artboardNestingBit = 0x08;

  /// Bit locking every property at once.
  static const int allBit = 0x80000000;

  /// Raw 32-bit flags, including bits not interpreted by this release.
  final int flags;

  /// Creates protection from raw [flags].
  const PsdLayerProtection({this.flags = 0});

  /// Creates protection from individual locks.
  factory PsdLayerProtection.create({
    bool transparency = false,
    bool pixels = false,
    bool position = false,
    bool artboardNesting = false,
    bool all = false,
  }) => PsdLayerProtection(
    flags: (transparency ? transparencyBit : 0) | (pixels ? pixelsBit : 0) | (position ? positionBit : 0) | (artboardNesting ? artboardNestingBit : 0) | (all ? allBit : 0),
  );

  /// Decodes an optional `lspf` [block].
  factory PsdLayerProtection.decode(PsdTaggedBlock? block) =>
      block == null || block.data.length < 4 ? const PsdLayerProtection() : PsdLayerProtection(flags: ByteData.sublistView(block.data).getUint32(0));

  /// Whether every property is locked.
  bool get all => flags & allBit != 0;

  /// Whether transparent pixels are locked.
  bool get transparency => all || flags & transparencyBit != 0;

  /// Whether image pixels are locked.
  bool get pixels => all || flags & pixelsBit != 0;

  /// Whether the layer position is locked.
  bool get position => all || flags & positionBit != 0;

  /// Whether automatic artboard nesting is prevented.
  bool get artboardNesting => all || flags & artboardNestingBit != 0;

  /// Encodes this protection as an `lspf` block.
  PsdTaggedBlock toBlock() => PsdTaggedBlock(key: 'lspf', data: (ByteData(4)..setUint32(0, flags)).buffer.asUint8List());
}

/// Background fill Photoshop draws behind an artboard.
enum PsdArtboardBackground {
  /// Opaque white.
  white(1),

  /// Opaque black.
  black(2),

  /// No background.
  transparent(3),

  /// The color stored in the artboard descriptor.
  custom(4);

  /// Value stored under `artboardBackgroundType`.
  final int code;

  /// Creates a background stored as [code].
  const PsdArtboardBackground(this.code);

  /// Returns the background stored as [code], or `null` when unknown.
  static PsdArtboardBackground? fromCode(int? code) {
    for (final PsdArtboardBackground background in values) {
      if (background.code == code) {
        return background;
      }
    }
    return null;
  }
}

/// Artboard settings stored on a group layer's `artb` block.
final class PsdArtboard {
  /// Complete artboard descriptor, including properties not modeled here.
  final PsDescriptor descriptor;

  /// Creates a view over an `artboard` [descriptor].
  const PsdArtboard({required this.descriptor});

  /// Creates an artboard covering the given document-space edges.
  factory PsdArtboard.create({
    required double left,
    required double top,
    required double right,
    required double bottom,
    PsdArtboardBackground background = PsdArtboardBackground.white,
    PsColor? color,
    String presetName = '',
  }) {
    if (!(right > left && bottom > top)) {
      throw const PsWriteException(message: 'Artboard bounds must have a positive size');
    }
    return PsdArtboard(
      descriptor: PsDescriptor(
        name: '\u0000',
        classId: 'artboard',
        items: [
          PsDescriptorItem(
            key: 'artboardRect',
            value: PsObjectValue(
              value: PsDescriptor(
                name: '\u0000',
                classId: 'classFloatRect',
                items: [
                  PsDescriptorItem(
                    key: 'Top ',
                    value: PsDoubleValue(value: top),
                  ),
                  PsDescriptorItem(
                    key: 'Left',
                    value: PsDoubleValue(value: left),
                  ),
                  PsDescriptorItem(
                    key: 'Btom',
                    value: PsDoubleValue(value: bottom),
                  ),
                  PsDescriptorItem(
                    key: 'Rght',
                    value: PsDoubleValue(value: right),
                  ),
                ],
              ),
            ),
          ),
          const PsDescriptorItem(
            key: 'guideIndeces',
            value: PsListValue(values: []),
          ),
          PsDescriptorItem(
            key: 'artboardPresetName',
            value: PsStringValue(value: '$presetName\u0000'),
          ),
          PsDescriptorItem(
            key: 'Clr ',
            value: PsObjectValue(value: (color ?? PsColor.rgb(red: 255, green: 255, blue: 255)).descriptor),
          ),
          PsDescriptorItem(
            key: 'artboardBackgroundType',
            value: PsIntegerValue(value: background.code),
          ),
        ],
      ),
    );
  }

  /// Decodes an `artb` [block], returning `null` when it is malformed.
  static PsdArtboard? tryDecode(Uint8List data) {
    final PsDescriptor? descriptor = _tryDecodeVersioned(data);
    if (descriptor == null || descriptor.classId != 'artboard') {
      return null;
    }
    final PsdArtboard artboard = PsdArtboard(descriptor: descriptor);
    final double? left = artboard.left;
    final double? top = artboard.top;
    final double? right = artboard.right;
    final double? bottom = artboard.bottom;
    if (left == null || top == null || right == null || bottom == null || right <= left || bottom <= top) {
      return null;
    }
    return artboard;
  }

  /// Left edge in document pixels.
  double? get left => _rectangle?.scalarValue('Left');

  /// Top edge in document pixels.
  double? get top => _rectangle?.scalarValue('Top ');

  /// Right edge in document pixels.
  double? get right => _rectangle?.scalarValue('Rght');

  /// Bottom edge in document pixels.
  double? get bottom => _rectangle?.scalarValue('Btom');

  /// Background drawn behind the artboard, or `null` for an unknown type.
  PsdArtboardBackground? get background => PsdArtboardBackground.fromCode(descriptor.integerValue('artboardBackgroundType'));

  /// Stored background color, used when [background] is custom.
  PsColor? get color {
    final PsDescriptor? value = descriptor.objectValue('Clr ');
    return value == null ? null : PsColor.fromDescriptor(value);
  }

  /// Name of the device preset the artboard was created from, or empty.
  String get presetName => descriptor.stringValue('artboardPresetName') ?? '';

  /// Encodes this artboard as an `artb` block.
  PsdTaggedBlock toBlock() => PsdTaggedBlock(key: 'artb', data: _encodeVersioned(descriptor));

  /// Bounds descriptor stored under `artboardRect`.
  PsDescriptor? get _rectangle => descriptor.objectValue('artboardRect');
}

/// Document-wide artboard defaults stored in the `artd` block.
final class PsdArtboardDefaults {
  /// Complete descriptor, including properties not modeled here.
  final PsDescriptor descriptor;

  /// Creates a view over an `artd` [descriptor].
  const PsdArtboardDefaults({required this.descriptor});

  /// Creates Photoshop's defaults for a document holding [count] artboards.
  factory PsdArtboardDefaults.create({
    required int count,
    PsdArtboardBackground defaultBackground = PsdArtboardBackground.white,
    PsColor? defaultColor,
  }) {
    PsDescriptorValue origin() => PsObjectValue(value: PsPoint.create(horizontal: 0, vertical: 0).descriptor);
    return PsdArtboardDefaults(
      descriptor: PsDescriptor(
        name: '\u0000',
        classId: 'null',
        items: [
          PsDescriptorItem(
            key: 'Cnt ',
            value: PsIntegerValue(value: count),
          ),
          PsDescriptorItem(key: 'autoExpandOffset', value: origin()),
          PsDescriptorItem(key: 'origin', value: origin()),
          const PsDescriptorItem(key: 'autoExpandEnabled', value: PsBooleanValue(value: true)),
          const PsDescriptorItem(key: 'autoNestEnabled', value: PsBooleanValue(value: true)),
          const PsDescriptorItem(key: 'autoPositionEnabled', value: PsBooleanValue(value: true)),
          const PsDescriptorItem(key: 'shrinkwrapOnSaveEnabled', value: PsBooleanValue(value: true)),
          PsDescriptorItem(
            key: 'docDefaultNewArtboardBackgroundColor',
            value: PsObjectValue(value: (defaultColor ?? PsColor.rgb(red: 255, green: 255, blue: 255)).descriptor),
          ),
          PsDescriptorItem(
            key: 'docDefaultNewArtboardBackgroundType',
            value: PsIntegerValue(value: defaultBackground.code),
          ),
        ],
      ),
    );
  }

  /// Decodes an `artd` block payload, returning `null` when it is malformed.
  static PsdArtboardDefaults? tryDecode(Uint8List data) {
    final PsDescriptor? descriptor = _tryDecodeVersioned(data);
    return descriptor == null ? null : PsdArtboardDefaults(descriptor: descriptor);
  }

  /// Number of artboards Photoshop recorded in the document.
  int? get count => descriptor.integerValue('Cnt ');

  /// Whether artboards grow automatically around their content.
  bool? get autoExpandEnabled => descriptor.booleanValue('autoExpandEnabled');

  /// Whether layers nest automatically into the artboard they are moved onto.
  bool? get autoNestEnabled => descriptor.booleanValue('autoNestEnabled');

  /// Whether new artboards are positioned automatically.
  bool? get autoPositionEnabled => descriptor.booleanValue('autoPositionEnabled');

  /// Whether the canvas shrinks to fit the artboards when saving.
  bool? get shrinkwrapOnSaveEnabled => descriptor.booleanValue('shrinkwrapOnSaveEnabled');

  /// Background given to new artboards, or `null` for an unknown type.
  PsdArtboardBackground? get defaultBackground => PsdArtboardBackground.fromCode(descriptor.integerValue('docDefaultNewArtboardBackgroundType'));

  /// Custom background color given to new artboards.
  PsColor? get defaultColor {
    final PsDescriptor? value = descriptor.objectValue('docDefaultNewArtboardBackgroundColor');
    return value == null ? null : PsColor.fromDescriptor(value);
  }

  /// Encodes these defaults as an `artd` block.
  PsdTaggedBlock toBlock() => PsdTaggedBlock(key: 'artd', data: _encodeVersioned(descriptor));
}

/// Decodes a version 16 descriptor followed only by zero padding.
PsDescriptor? _tryDecodeVersioned(Uint8List data) {
  try {
    final ({PsVersionedDescriptor value, int bytesRead}) decoded = PsVersionedDescriptorCodec.decodePrefix(data, expectedVersion: 16);
    if (data.skip(decoded.bytesRead).any((value) => value != 0)) {
      return null;
    }
    return decoded.value.descriptor;
  } on FormatException {
    return null;
  }
}

/// Encodes a version 16 [descriptor] padded to four bytes.
Uint8List _encodeVersioned(PsDescriptor descriptor) {
  final PsBinaryWriter writer = PsBinaryWriter()..writeBytes(PsVersionedDescriptorCodec.encode(PsVersionedDescriptor(descriptor: descriptor)));
  writer.writeZeros((4 - writer.length % 4) % 4);
  return writer.takeBytes();
}
