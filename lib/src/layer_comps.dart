import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:psdkit/src/effects.dart';
import 'package:psdkit/src/model.dart';

part 'layer_comps/blending.dart';
part 'layer_comps/layer_state.dart';
part 'layer_comps/metadata.dart';

/// Maximum number of layer compositions accepted from untrusted metadata.
const int _maximumLayerComps = 10000;

/// Maximum unrelated entries accepted in one shared-metadata block.
const int _maximumExtraSharedMetadataEntries = 1024;

/// A finite point stored in Photoshop layer-composition metadata.
typedef PsdLayerCompPoint = ({double horizontal, double vertical});

/// Encodes and decodes per-layer Photoshop `shmd`/`cmls` metadata.
abstract final class PsdLayerCompsCodec {
  /// Decodes the last `cmls` entry on [layer], or `null` when unavailable.
  static PsdLayerCompLayerData? tryDecodeLayer(PsdLayer layer) {
    final PsdTaggedBlock? block = layer.taggedBlock('shmd');
    if (block == null) {
      return null;
    }
    try {
      final List<_SharedMetadataEntry> entries = _decodeSharedMetadata(
        block.data,
      );
      for (int index = entries.length - 1; index >= 0; index--) {
        final _SharedMetadataEntry entry = entries[index];
        if (entry.key != 'cmls') {
          continue;
        }
        final PsDescriptor descriptor = _decodeVersionedDescriptor(
          entry.data,
        );
        final PsdLayerCompLayerData result = PsdLayerCompLayerData(
          descriptor: descriptor,
        );
        if (result.layerIdentifier == null || result.originalEffectsReferencePoint == null || descriptor.value('layerSettings') is! PsListValue) {
          return null;
        }
        return result;
      }
    } on Object {
      return null;
    }
    return null;
  }

  /// Returns [layer] with its `cmls` entry replaced by [data].
  static PsdLayer withLayerData(
    PsdLayer layer,
    PsdLayerCompLayerData? data,
  ) {
    final PsdTaggedBlock? block = layer.taggedBlock('shmd');
    List<_SharedMetadataEntry> entries;
    if (block == null) {
      entries = [];
    } else {
      try {
        entries = _decodeSharedMetadata(block.data);
      } on Object {
        if (data == null) {
          return layer;
        }
        entries = [];
      }
    }
    final List<_SharedMetadataEntry> updated = [
      for (final _SharedMetadataEntry entry in entries)
        if (entry.key != 'cmls') entry,
      if (data != null)
        _SharedMetadataEntry(
          signature: '8BIM',
          key: 'cmls',
          copyOnSheetDuplication: false,
          data: _encodeVersionedDescriptor(data.descriptor),
        ),
    ];
    return _copyLayerWithBlock(
      layer,
      updated.isEmpty
          ? null
          : PsdTaggedBlock(
              key: 'shmd',
              data: _encodeSharedMetadata(updated),
            ),
      key: 'shmd',
    );
  }
}

/// Convenient layer-composition access on individual layer records.
extension PsdLayerLayerComps on PsdLayer {
  /// Decoded per-layer composition metadata, when present and valid.
  PsdLayerCompLayerData? get layerCompData => PsdLayerCompsCodec.tryDecodeLayer(this);

  /// Returns a layer whose per-layer composition metadata is [data].
  PsdLayer withLayerCompData(PsdLayerCompLayerData? data) => PsdLayerCompsCodec.withLayerData(this, data);
}
