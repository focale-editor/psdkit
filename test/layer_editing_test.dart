import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Verifies that semantic edits retain the rest of a layer's metadata.
void main() {
  final List<_LayerEditCase> cases = [
    (
      name: 'effects',
      keys: ['lfx2', 'lmfx', 'lrFX'],
      replacementKey: 'lfx2',
      edit: (layer) => layer.withEffects(PsdLayerEffects.create()),
    ),
    (
      name: 'adjustment',
      keys: ['brit', 'curv', 'CgEd'],
      replacementKey: 'nvrt',
      edit: (layer) => layer.withAdjustment(PsdInvertAdjustment()),
    ),
    (
      name: 'vector mask',
      keys: ['vmsk', 'vsms'],
      replacementKey: 'vmsk',
      edit: (layer) => layer.withVectorMask(PsdVectorMask(path: PsdVectorPath.fromSubpaths(subpaths: []))),
    ),
    (
      name: 'smart object',
      keys: ['SoLd', 'SoLE', 'plLd'],
      replacementKey: 'SoLd',
      edit: (layer) => layer.withSmartObject(PsdRawSmartObject(blockKey: 'SoLd', data: Uint8List.fromList([1, 2, 3]))),
    ),
  ];

  for (final _LayerEditCase testCase in cases) {
    test('${testCase.name} preserves metadata and unrelated block order', () {
      final PsdTaggedBlock first = PsdTaggedBlock(key: 'head', data: Uint8List.fromList([10]));
      final PsdTaggedBlock last = PsdTaggedBlock(key: 'tail', data: Uint8List.fromList([20]));
      final PsdLayer source = PsdLayer(
        rectangle: const .fromSize(width: 2, height: 3),
        name: 'Preserved',
        channels: [PsdChannel(id: 0, data: Uint8List(6))],
        blendMode: 'mul ',
        opacity: 73,
        clipping: 1,
        flags: 3,
        mask: PsdLayerMask(
          rectangle: const .fromSize(width: 1, height: 2),
          defaultColor: 255,
          flags: 2,
          data: Uint8List.fromList([4, 5]),
        ),
        blendingRanges: Uint8List.fromList([6, 7]),
        additionalInfo: [
          first,
          for (final String key in testCase.keys) PsdTaggedBlock(key: key, data: Uint8List(0)),
          last,
        ],
        writesUnicodeName: false,
      );

      final PsdLayer edited = testCase.edit(source);

      expect(edited, isNot(same(source)));
      expect(edited.rectangle, same(source.rectangle));
      expect(edited.name, source.name);
      expect(edited.channels, same(source.channels));
      expect(edited.blendMode, source.blendMode);
      expect(edited.opacity, source.opacity);
      expect(edited.clipping, source.clipping);
      expect(edited.flags, source.flags);
      expect(edited.mask, same(source.mask));
      expect(edited.blendingRanges, same(source.blendingRanges));
      expect(edited.writesUnicodeName, isFalse);
      expect(edited.additionalInfo.map((block) => block.key), ['head', 'tail', testCase.replacementKey]);
      expect(edited.additionalInfo[0], same(first));
      expect(edited.additionalInfo[1], same(last));
      expect(source.additionalInfo.map((block) => block.key), ['head', ...testCase.keys, 'tail']);
    });
  }
}

/// An edit and the competing tagged blocks it replaces.
typedef _LayerEditCase = ({String name, List<String> keys, String replacementKey, PsdLayer Function(PsdLayer) edit});
