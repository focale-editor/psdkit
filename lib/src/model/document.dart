part of '../model.dart';

/// An in-memory PSD or PSB document.
final class PsdDocument {
  /// Container version.
  final PsdVersion version;

  /// Canvas width in pixels.
  final int width;

  /// Canvas height in pixels.
  final int height;

  /// Number of channels in the merged image.
  final int channels;

  /// Bits per sample: 1, 8, 16, or 32.
  final int depth;

  /// Document colour model.
  final PsdColorMode colorMode;

  /// Palette, duotone settings, or other mode-specific bytes.
  final Uint8List colorModeData;

  /// Photoshop image resource blocks.
  final List<PsdImageResource> imageResources;

  /// Flat PSD layer-record order, including group divider records.
  final List<PsdLayer> layers;

  /// Merged-image channels in file order.
  final List<Uint8List> mergedImage;

  /// Preferred merged-image encoding.
  final PsdCompression mergedImageCompression;

  /// Whether a negative layer count advertised merged transparency.
  final bool mergedTransparency;

  /// Opaque global layer-mask payload.
  final Uint8List globalLayerMaskData;

  /// Tagged blocks following global layer-mask information.
  final List<PsdTaggedBlock> additionalLayerInfo;

  /// Recoverable read issues; deferred merged decoding can append warnings.
  ///
  /// Decoded documents expose an unmodifiable view. No layer damage or
  /// allocation-limit failure is converted into a warning.
  final List<PsdReadWarning> warnings;

  /// Creates a document from planar, uncompressed channel samples.
  PsdDocument({
    required this.width,
    required this.height,
    required this.channels,
    required this.depth,
    required this.colorMode,
    required this.mergedImage,
    this.version = PsdVersion.psd,
    this.warnings = const [],
    Uint8List? colorModeData,
    this.imageResources = const [],
    this.layers = const [],
    this.mergedImageCompression = PsdCompression.rle,
    this.mergedTransparency = false,
    Uint8List? globalLayerMaskData,
    this.additionalLayerInfo = const [],
  }) : colorModeData = colorModeData ?? Uint8List(0),
       globalLayerMaskData = globalLayerMaskData ?? Uint8List(0);

  /// Resolves one type layer with the document-level kerning and OpenType settings.
  PsdTextContent? textContentFor(PsdLayer layer) {
    final PsdTypeTool? typeTool = layer.typeTool;
    return typeTool == null ? null : globalTextEngineData?.contentFor(typeTool) ?? typeTool.content;
  }

  /// Updates a type layer and its existing global text object in one operation.
  ///
  /// A shared or invalid `TextIndex` is rejected instead of changing another layer.
  /// Unsupported global layout/paragraph/style edits throw rather than desynchronize Txt2.
  /// Layer raster pixels and the merged preview still need rendering by the host.
  PsdDocument withTextContent(int layerIndex, PsdTextContent content) {
    RangeError.checkValidIndex(layerIndex, layers);
    final PsdLayer layer = layers[layerIndex];
    final PsdTypeTool? typeTool = layer.typeTool;
    if (typeTool == null) {
      throw ArgumentError('The selected layer has no TySh text');
    }
    final PsdGlobalTextEngineData? global = globalTextEngineData;
    if (global != null && layers.where((value) => value.typeTool?.textIndex == typeTool.textIndex).length != 1) {
      throw StateError('TextIndex is shared by multiple layers');
    }
    if (global == null &&
        content.styleRuns.any((run) => run.style.resolvedKerningMode == PsdTextKerning.optical || run.style.openTypeFeatures.entries.any((entry) => entry.key.startsWith('ss') && entry.value != 0))) {
      throw StateError('Optical kerning and stylistic sets require a Photoshop Txt2 template');
    }
    final List<PsdLayer> updated = [...layers]..[layerIndex] = layer.withTypeTool(typeTool.withContent(content));
    final PsdDocument result = copyPsdDocument(this, layers: updated);
    return global == null ? result : result.withGlobalTextEngineData(global.withContent(typeTool.textIndex, content, previous: typeTool.content));
  }

  /// Named document paths stored in image-resource ids 2000 through 2997.
  List<PsdNamedPath> get namedPaths {
    final List<PsdNamedPath> result = <PsdNamedPath>[];
    for (final PsdImageResource resource in imageResources) {
      if (resource.id < 2000 || resource.id > 2997) {
        continue;
      }
      final PsdVectorPath? path = PsdVectorPathCodec.tryDecode(resource.data);
      if (path != null) {
        result.add(PsdNamedPath(resourceId: resource.id, name: resource.name, path: path, signature: resource.signature));
      }
    }
    return result;
  }

  /// Decoded document-level linked-resource blocks in file order.
  List<PsdLinkedResourceBlock> get linkedResourceBlocks {
    final List<PsdLinkedResourceBlock> result = <PsdLinkedResourceBlock>[];
    for (final PsdTaggedBlock block in additionalLayerInfo) {
      if (block.isForeignByteOrder || !psdLinkedResourceKeys.contains(block.key)) {
        continue;
      }
      final PsdLinkedResourceBlock? decoded = PsdLinkedResourceCodec.tryDecode(block.data, key: block.key);
      if (decoded != null) {
        result.add(decoded);
      }
    }
    return result;
  }

  /// All semantically decoded embedded, external, and alias resources.
  List<PsdLinkedResource> get linkedResources => <PsdLinkedResource>[
    for (final PsdLinkedResourceBlock block in linkedResourceBlocks) ...block.resources,
  ];

  /// Document-level `Txt2` text-engine data, when present.
  PsdGlobalTextEngineData? get globalTextEngineData {
    for (final PsdTaggedBlock block in additionalLayerInfo.reversed) {
      if (block.key == 'Txt2' && !block.isForeignByteOrder) {
        return PsdGlobalTextEngineData(data: block.data);
      }
    }
    return null;
  }

  /// Document-wide artboard defaults from the `artd` block, when present.
  PsdArtboardDefaults? get artboardDefaults {
    for (final PsdTaggedBlock block in additionalLayerInfo.reversed) {
      if (block.key == 'artd' && !block.isForeignByteOrder) {
        return PsdArtboardDefaults.tryDecode(block.data);
      }
    }
    return null;
  }

  /// Returns a copy whose `artd` block encodes [defaults], or none when `null`.
  PsdDocument withArtboardDefaults(PsdArtboardDefaults? defaults) => copyPsdDocument(
    this,
    additionalLayerInfo: [
      for (final PsdTaggedBlock block in additionalLayerInfo)
        if (block.key != 'artd') block,
      ?defaults?.toBlock(),
    ],
  );

  /// Patterns embedded in document-level `Patt`, `Pat2`, and `Pat3` blocks.
  ///
  /// Layer effects and fills refer to these patterns by identifier. Malformed
  /// records are skipped, so a damaged block never hides the remaining ones.
  List<PsPattern> get patterns => [
    for (final PsdTaggedBlock block in additionalLayerInfo)
      if (!block.isForeignByteOrder && _patternBlockKeys.contains(block.key)) ..._decodePatternBlock(block.data),
  ];

  /// Returns the embedded pattern whose identifier is [id], when present.
  PsPattern? patternFor(String id) {
    for (final PsPattern pattern in patterns) {
      if (pattern.id == id) {
        return pattern;
      }
    }
    return null;
  }

  /// Returns a copy whose document-level pattern blocks contain [patterns].
  ///
  /// The patterns are written to the block matching the document [depth]:
  /// `Patt` for 8-bit, `Pat2` for 16-bit, and `Pat3` for 32-bit documents.
  /// Passing an empty list removes every pattern block.
  PsdDocument withPatterns(List<PsPattern> patterns) => copyPsdDocument(
    this,
    additionalLayerInfo: [
      for (final PsdTaggedBlock block in additionalLayerInfo)
        if (!_patternBlockKeys.contains(block.key)) block,
      if (patterns.isNotEmpty)
        PsdTaggedBlock(
          key: switch (depth) {
            16 => 'Pat2',
            32 => 'Pat3',
            _ => 'Patt',
          },
          data: PsPatternBlockEncoder.encodeAll(patterns),
        ),
    ],
  );

  /// Returns a copy whose document-level `Txt2` block contains [engineData].
  ///
  /// Passing `null` removes every existing global text-engine block.
  PsdDocument withGlobalTextEngineData(PsdGlobalTextEngineData? engineData) => copyPsdDocument(
    this,
    additionalLayerInfo: <PsdTaggedBlock>[
      for (final PsdTaggedBlock block in additionalLayerInfo)
        if (block.key != 'Txt2') block,
      if (engineData != null) PsdTaggedBlock(key: 'Txt2', data: engineData.data),
    ],
  );

  /// Returns a copy whose document path resources are [paths].
  PsdDocument withNamedPaths(List<PsdNamedPath> paths) {
    final Set<int> ids = <int>{};
    for (final PsdNamedPath path in paths) {
      if (path.resourceId < 2000 || path.resourceId > 2997) {
        throw PsWriteException(message: 'Named path resource id ${path.resourceId} must be from 2000 through 2997');
      }
      if (!ids.add(path.resourceId)) {
        throw PsWriteException(message: 'Duplicate named path resource id ${path.resourceId}');
      }
    }
    return copyPsdDocument(
      this,
      imageResources: <PsdImageResource>[
        for (final PsdImageResource resource in imageResources)
          if (resource.id < 2000 || resource.id > 2997) resource,
        for (final PsdNamedPath path in paths)
          PsdImageResource(
            id: path.resourceId,
            name: path.name,
            signature: path.signature,
            data: PsdVectorPathCodec.encode(path.path),
          ),
      ],
    );
  }

  /// Returns the resource referenced by [layer]'s smart-object identifier.
  PsdLinkedResource? linkedResourceFor(PsdLayer layer) {
    final String? id = layer.smartObject?.linkedResourceId;
    if (id == null) {
      return null;
    }
    for (final PsdLinkedResource resource in linkedResources) {
      if (resource.id == id) {
        return resource;
      }
    }
    return null;
  }

  /// Decodes filter-effect metadata without inflating any cache or mask pixels.
  ///
  /// Malformed payloads throw [PsFormatException]; callers may keep the original
  /// tagged blocks opaque rather than interpreting them as absent masks.
  List<PsdFilterEffects> get filterEffectBlocks => [
    for (final PsdTaggedBlock block in additionalLayerInfo)
      if (!block.isForeignByteOrder && psdFilterEffectsKeys.contains(block.key)) PsdFilterEffectsCodec.decode(block.data),
  ];

  /// Finds an unambiguous cache by placement identity, never by source identity.
  PsdFilterEffect? filterEffectFor(PsdLayer layer) {
    final PsdSmartObjectLayerData? smartObject = layer.smartObject;
    final String? id = smartObject is PsdDescriptorSmartObject ? smartObject.placementId : null;
    if (id == null || id.isEmpty) {
      return null;
    }
    PsdFilterEffect? result;
    for (final PsdFilterEffects block in filterEffectBlocks) {
      for (final PsdFilterEffect effect in block.effects) {
        if (effect.id != id) {
          continue;
        }
        if (result != null) {
          return null;
        }
        result = effect;
      }
    }
    return result;
  }

  /// Returns a copy replacing all filter-cache blocks with one `FEid` payload.
  PsdDocument withFilterEffects(PsdFilterEffects effects) => copyPsdDocument(
    this,
    additionalLayerInfo: [
      for (final PsdTaggedBlock block in additionalLayerInfo)
        if (!psdFilterEffectsKeys.contains(block.key)) block,
      PsdTaggedBlock(key: 'FEid', data: PsdFilterEffectsCodec.encode(effects)),
    ],
  );

  /// Returns a copy whose linked-resource blocks are [blocks].
  PsdDocument withLinkedResourceBlocks(List<PsdLinkedResourceBlock> blocks) => copyPsdDocument(
    this,
    additionalLayerInfo: <PsdTaggedBlock>[
      for (final PsdTaggedBlock block in additionalLayerInfo)
        if (!psdLinkedResourceKeys.contains(block.key)) block,
      for (final PsdLinkedResourceBlock block in blocks) PsdTaggedBlock(key: block.blockKey, data: PsdLinkedResourceCodec.encode(block)),
    ],
  );

  /// Returns a copy containing [resources] in one modern `lnk2` block.
  PsdDocument withLinkedResources(List<PsdLinkedResource> resources) => withLinkedResourceBlocks(
    resources.isEmpty ? const <PsdLinkedResourceBlock>[] : <PsdLinkedResourceBlock>[PsdLinkedResourceBlock(entries: resources)],
  );
}

/// Document-level tagged-block keys holding embedded patterns.
const Set<String> _patternBlockKeys = {'Patt', 'Pat2', 'Pat3'};

/// Maximum number of patterns accepted from one untrusted pattern block.
const int _maximumPatternsPerBlock = 100000;

/// Decodes every well-formed pattern record in one pattern block [data].
List<PsPattern> _decodePatternBlock(Uint8List data) {
  try {
    return PsPatternBlockDecoder.decodeAll(
      reader: PsBinaryReader(bytes: data),
      maxPatterns: _maximumPatternsPerBlock,
    ).patterns;
  } on PsFormatException {
    return const [];
  }
}
