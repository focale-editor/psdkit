part of '../model.dart';

/// A Photoshop layer record and its decoded channels.
final class PsdLayer {
  /// Pixel bounds in document coordinates.
  final PsdRectangle rectangle;

  /// Unicode display name, falling back to the Pascal name on import.
  final String name;

  /// Decoded planar channels.
  final List<PsdChannel> channels;

  /// Four-character Photoshop blend-mode key.
  final String blendMode;

  /// Opacity from 0 through 255.
  final int opacity;

  /// Clipping flag, normally 0 or 1.
  final int clipping;

  /// Raw layer flags. Bit 1 means hidden in PSD files.
  final int flags;

  /// Raster-mask metadata, when present.
  final PsdLayerMask? mask;

  /// Opaque layer blending-ranges payload.
  final Uint8List blendingRanges;

  /// Tagged data such as text, effects, vector paths, and adjustment settings.
  final List<PsdTaggedBlock> additionalInfo;

  /// Whether encoding adds a `luni` Unicode-name block when [additionalInfo] has none.
  ///
  /// Photoshop writes one for every layer, so new layers get one. Layers read
  /// from a file without one, such as ImageReady's, keep the file's layout,
  /// unless their name cannot be stored in the one-byte Pascal name.
  final bool writesUnicodeName;

  /// Creates a layer.
  PsdLayer({
    required this.rectangle,
    required this.name,
    this.channels = const [],
    this.blendMode = 'norm',
    this.opacity = 255,
    this.clipping = 0,
    this.flags = 0,
    this.mask,
    Uint8List? blendingRanges,
    this.additionalInfo = const [],
    this.writesUnicodeName = true,
  }) : blendingRanges = blendingRanges ?? Uint8List(0);

  /// Whether the layer is visible.
  bool get visible => flags & 0x02 == 0;

  /// Decoded fill or adjustment settings, when the layer contains them.
  ///
  /// Brightness/contrast settings come from the `CgEd` descriptor modern
  /// Photoshop writes, falling back to the legacy `brit` values without it.
  PsdAdjustment? get adjustment {
    for (final PsdTaggedBlock block in additionalInfo.reversed) {
      if (psdAdjustmentKeys.contains(block.key)) {
        final PsdAdjustment? decoded = PsdAdjustmentCodec.tryDecode(block.data, key: block.key);
        return decoded is PsdBrightnessContrastAdjustment ? _modernBrightnessContrast(decoded) ?? decoded : decoded;
      }
    }
    return null;
  }

  /// Reads the `CgEd` settings overriding [legacy], when the layer has them.
  PsdBrightnessContrastAdjustment? _modernBrightnessContrast(PsdBrightnessContrastAdjustment legacy) {
    final PsdTaggedBlock? block = taggedBlock('CgEd');
    if (block == null) {
      return null;
    }
    try {
      final PsDescriptor descriptor = PsVersionedDescriptorCodec.decodePrefix(block.data).value.descriptor;
      return PsdBrightnessContrastAdjustment.fromContentGeneratorDescriptor(descriptor, trailingData: legacy.trailingData);
    } on FormatException {
      return null;
    }
  }

  /// Decoded Photoshop type-tool data, when this is a supported text layer.
  PsdTypeTool? get typeTool {
    final PsdTaggedBlock? block = taggedBlock('TySh');
    return block == null ? null : PsdTypeToolCodec.tryDecode(block.data);
  }

  /// Decoded Photoshop 5.x type-tool data, when the legacy block is present.
  PsdLegacyTypeTool? get legacyTypeTool {
    final PsdTaggedBlock? block = taggedBlock('tySh');
    return block == null ? null : PsdLegacyTypeToolCodec.tryDecode(block.data);
  }

  /// Decoded Photoshop layer effects, preferring the modern descriptor block.
  PsdLayerEffects? get effects {
    for (final String key in const <String>['lfx2', 'lmfx', 'lrFX']) {
      final PsdTaggedBlock? block = taggedBlock(key);
      if (block != null) {
        final PsdLayerEffects? decoded = PsdLayerEffectsCodec.tryDecode(block.data, key: key);
        if (decoded != null) {
          return decoded;
        }
      }
    }
    return null;
  }

  /// Decoded layer vector mask, preferring the primary `vmsk` block.
  PsdVectorMask? get vectorMask {
    for (final String key in const <String>['vmsk', 'vsms']) {
      final PsdTaggedBlock? block = taggedBlock(key);
      if (block != null) {
        final PsdVectorMask? decoded = PsdVectorMaskCodec.tryDecode(block.data, key: key);
        if (decoded != null) {
          return decoded;
        }
      }
    }
    return null;
  }

  /// Decoded modern or legacy smart-object metadata for this layer.
  PsdSmartObjectLayerData? get smartObject {
    for (final String key in const <String>['SoLE', 'SoLd', 'plLd']) {
      final PsdTaggedBlock? block = taggedBlock(key);
      if (block != null) {
        final PsdSmartObjectLayerData? decoded = PsdSmartObjectCodec.tryDecode(block.data, key: key);
        if (decoded != null) {
          return decoded;
        }
      }
    }
    return null;
  }

  /// Stable Photoshop layer id, when the `lyid` block is present.
  int? get id {
    final PsdTaggedBlock? block = taggedBlock('lyid');
    if (block == null || block.data.length < 4) {
      return null;
    }
    return ByteData.sublistView(block.data).getUint32(0);
  }

  /// Group marker represented by the `lsct` or `lsdk` block.
  PsdSectionType get sectionType {
    final PsdTaggedBlock? block = taggedBlock('lsct') ?? taggedBlock('lsdk');
    if (block == null || block.data.length < 4) {
      return PsdSectionType.other;
    }
    final int code = ByteData.sublistView(block.data).getUint32(0);
    return PsdSectionType.values.firstWhere(
      (value) => value.code == code,
      orElse: () => PsdSectionType.other,
    );
  }

  /// Paint of a fill or shape layer.
  ///
  /// The `vscg` shape-fill block takes precedence over the fill-layer block,
  /// matching how Photoshop reads shape layers.
  PsdFillContent? get fill {
    final PsdTaggedBlock? shapeFill = taggedBlock('vscg');
    if (shapeFill != null) {
      final PsdFillContent? decoded = PsdFillContent.tryDecodeShapeFill(shapeFill.data);
      if (decoded != null) {
        return decoded;
      }
    }
    return switch (adjustment) {
      final PsdDescriptorAdjustment adjustment => adjustment.fill,
      _ => null,
    };
  }

  /// Stroke and fill visibility of a shape layer, when present and well formed.
  PsdShapeStroke? get shapeStroke {
    final PsdTaggedBlock? block = taggedBlock('vstk');
    return block == null ? null : PsdShapeStroke.tryDecode(block.data);
  }

  /// Advanced blending options such as fill opacity and knockout.
  PsdLayerBlendingOptions get blendingOptions => PsdLayerBlendingOptions.decode(taggedBlock);

  /// Editing locks from the `lspf` block and the record's transparency flag.
  PsdLayerProtection get protection {
    final PsdLayerProtection stored = PsdLayerProtection.decode(taggedBlock('lspf'));
    return flags & PsdLayerProtection.transparencyBit == 0 ? stored : PsdLayerProtection(flags: stored.flags | PsdLayerProtection.transparencyBit);
  }

  /// Layers-panel color label, or `null` for a label newer than this release.
  PsdSheetColor? get sheetColor {
    final PsdTaggedBlock? block = taggedBlock('lclr');
    return block == null || block.data.length < 2 ? PsdSheetColor.none : PsdSheetColor.fromCode(ByteData.sublistView(block.data).getUint16(0));
  }

  /// Artboard settings of a group layer, when present and well formed.
  PsdArtboard? get artboard {
    final PsdTaggedBlock? block = taggedBlock('artb');
    return block == null ? null : PsdArtboard.tryDecode(block.data);
  }

  /// Returns the last tagged block matching [key].
  PsdTaggedBlock? taggedBlock(String key) {
    for (final PsdTaggedBlock block in additionalInfo.reversed) {
      if (block.key == key) {
        return block;
      }
    }
    return null;
  }

  /// Returns the channel with [id], when present.
  PsdChannel? channel(int id) {
    for (final PsdChannel channel in channels) {
      if (channel.id == id) {
        return channel;
      }
    }
    return null;
  }

  /// Returns a copy whose `TySh` block contains [typeTool].
  PsdLayer withTypeTool(PsdTypeTool typeTool) => _withTextBlock(
    PsdTaggedBlock(key: 'TySh', data: PsdTypeToolCodec.encode(typeTool)),
    obsoleteKey: 'tySh',
  );

  /// Returns a copy whose `tySh` block contains Photoshop 5.x [typeTool] data.
  ///
  /// Any modern `TySh` block is removed to avoid two conflicting text records.
  PsdLayer withLegacyTypeTool(PsdLegacyTypeTool typeTool) => _withTextBlock(
    PsdTaggedBlock(key: 'tySh', data: PsdLegacyTypeToolCodec.encode(typeTool)),
    obsoleteKey: 'TySh',
  );

  /// Returns a copy whose effect blocks contain [effects].
  ///
  /// Replacing effects removes stale modern and legacy effect blocks so that
  /// Photoshop cannot select an older conflicting representation.
  PsdLayer withEffects(PsdLayerEffects effects) => _withBlocks(
    const {'lfx2', 'lmfx', 'lrFX'},
    [PsdTaggedBlock(key: effects.blockKey, data: PsdLayerEffectsCodec.encode(effects))],
  );

  /// Returns a copy whose fill or adjustment block contains [adjustment].
  ///
  /// Existing adjustment blocks are removed to prevent Photoshop from choosing
  /// a stale conflicting representation. The `CgEd` block, which records the
  /// modern brightness/contrast settings or the name of the preset an
  /// adjustment came from, is rewritten for modern brightness/contrast and
  /// otherwise dropped, since it would describe the replaced values.
  PsdLayer withAdjustment(PsdAdjustment adjustment) => _withBlocks(
    {...psdAdjustmentKeys, 'CgEd'},
    [
      PsdTaggedBlock(key: adjustment.blockKey, data: PsdAdjustmentCodec.encode(adjustment)),
      if (adjustment case PsdBrightnessContrastAdjustment(useLegacy: false))
        PsdTaggedBlock(
          key: 'CgEd',
          data: PsVersionedDescriptorCodec.encode(PsVersionedDescriptor(descriptor: adjustment.toContentGeneratorDescriptor())),
        ),
    ],
  );

  /// Returns a copy whose vector-mask block contains [mask].
  PsdLayer withVectorMask(PsdVectorMask mask) => _withBlocks(
    const {'vmsk', 'vsms'},
    [PsdTaggedBlock(key: mask.blockKey, data: PsdVectorMaskCodec.encode(mask))],
  );

  /// Returns a copy whose smart-object block contains [smartObject].
  ///
  /// Older and newer placed-layer blocks are removed to prevent Photoshop from
  /// selecting stale metadata for the same layer.
  PsdLayer withSmartObject(PsdSmartObjectLayerData smartObject) => _withBlocks(
    psdSmartObjectLayerKeys,
    [PsdTaggedBlock(key: smartObject.blockKey, data: PsdSmartObjectCodec.encode(smartObject))],
  );

  /// Returns a copy painted with [content].
  ///
  /// The fill-layer block is replaced, and an existing `vscg` shape-fill block
  /// is updated as well so both representations stay consistent.
  PsdLayer withFill(PsdFillContent content) => _withBlocks(
    {...psdAdjustmentKeys, 'vscg'},
    [
      PsdTaggedBlock(key: content.kind.blockKey, data: PsdAdjustmentCodec.encode(content.toAdjustment())),
      if (taggedBlock('vscg') != null) content.toShapeFillBlock(),
    ],
  );

  /// Returns a copy whose `vstk` block encodes [stroke], or none when `null`.
  PsdLayer withShapeStroke(PsdShapeStroke? stroke) => _withBlocks(const {'vstk'}, [?stroke?.toBlock()]);

  /// Returns a copy whose advanced blending blocks encode [options].
  PsdLayer withBlendingOptions(PsdLayerBlendingOptions options) => _withBlocks(PsdLayerBlendingOptions.blockKeys, options.toBlocks());

  /// Returns a copy locked by [protection].
  ///
  /// The record's transparency flag is kept in sync with the `lspf` block.
  PsdLayer withProtection(PsdLayerProtection protection) => _withBlocks(
    const {'lspf'},
    [protection.toBlock()],
    flags: protection.transparency ? flags | PsdLayerProtection.transparencyBit : flags & ~PsdLayerProtection.transparencyBit,
  );

  /// Returns a copy labeled with [color].
  PsdLayer withSheetColor(PsdSheetColor color) => _withBlocks(
    const {'lclr'},
    [
      PsdTaggedBlock(key: 'lclr', data: (ByteData(8)..setUint16(0, color.code)).buffer.asUint8List()),
    ],
  );

  /// Returns a copy marked as [artboard], or unmarked when it is `null`.
  PsdLayer withArtboard(PsdArtboard? artboard) => _withBlocks(const {'artb'}, [?artboard?.toBlock()]);

  /// Replaces the first matching text block and removes conflicting versions.
  ///
  /// Existing text keeps its position among unrelated blocks. A newly added
  /// text block is appended, and duplicate text blocks are removed.
  PsdLayer _withTextBlock(PsdTaggedBlock replacement, {required String obsoleteKey}) {
    final List<PsdTaggedBlock> blocks = [];
    bool replaced = false;
    for (final PsdTaggedBlock block in additionalInfo) {
      if (block.key == replacement.key) {
        if (!replaced) {
          blocks.add(replacement);
          replaced = true;
        }
      } else if (block.key != obsoleteKey) {
        blocks.add(block);
      }
    }
    if (!replaced) {
      blocks.add(replacement);
    }
    return copyPsdLayer(this, additionalInfo: blocks);
  }

  /// Returns a copy whose blocks under [keys] are replaced by [replacements].
  PsdLayer _withBlocks(Set<String> keys, List<PsdTaggedBlock> replacements, {int? flags}) => copyPsdLayer(
    this,
    flags: flags,
    additionalInfo: [
      for (final PsdTaggedBlock block in additionalInfo)
        if (!keys.contains(block.key)) block,
      ...replacements,
    ],
  );
}
