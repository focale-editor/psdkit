part of '../codec.dart';

/// Chooses ordinary layer info or one depth-specific tagged block.
///
/// When `alternativeKey` is present, exactly one block in `blocks` has that key.
/// Its payload is empty when a progressive writer will supply the pixels later.
typedef _PsdLayerInfoLayout = ({String? alternativeKey, List<PsdTaggedBlock> blocks});

/// Plans layer placement and removes stale alternatives consistently in both writers.
_PsdLayerInfoLayout _layerInfoLayout({
  required int depth,
  required bool hasLayers,
  required List<PsdTaggedBlock> blocks,
  Uint8List? encodedLayers,
}) {
  final String key = _alternativeLayerInfoKey(depth);
  final bool hasAlternative = _alternativeLayerInfo(blocks, depth) != null;
  if (hasLayers && (depth == 16 || depth == 32 || hasAlternative)) {
    return (
      alternativeKey: key,
      blocks: _replaceAlternativeLayerInfo(blocks, key: key, data: encodedLayers ?? Uint8List(0)),
    );
  }
  return (
    alternativeKey: null,
    blocks: !hasLayers && hasAlternative ? _removeAlternativeLayerInfo(blocks, key) : blocks,
  );
}

/// Selects the layer-info key corresponding to a document sample depth.
String _alternativeLayerInfoKey(int depth) => switch (depth) {
  16 => 'Lr16',
  32 => 'Lr32',
  _ => 'Layr',
};

/// Removes a depth-specific layer block after all model layers were deleted.
List<PsdTaggedBlock> _removeAlternativeLayerInfo(List<PsdTaggedBlock> blocks, String key) => [
  for (final PsdTaggedBlock block in blocks)
    if (block.key != key) block,
];

/// Replaces stale alternative layer blocks with one freshly encoded payload.
List<PsdTaggedBlock> _replaceAlternativeLayerInfo(List<PsdTaggedBlock> blocks, {required String key, required Uint8List data}) {
  final List<PsdTaggedBlock> result = [];
  bool inserted = false;
  for (final PsdTaggedBlock block in blocks) {
    if (block.key == 'Layr' || block.key == 'Lr16' || block.key == 'Lr32') {
      if (!inserted) {
        result.add(PsdTaggedBlock(key: key, signature: block.signature, data: data));
        inserted = true;
      }
    } else {
      result.add(block);
    }
  }
  if (!inserted) {
    result.add(PsdTaggedBlock(key: key, data: data));
  }
  return result;
}
