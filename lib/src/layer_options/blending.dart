part of '../layer_options.dart';

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
