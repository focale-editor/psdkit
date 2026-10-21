import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Verifies that semantic edits retain the rest of a layer's metadata.
void main() {
  final Map<String, PsdLayer Function(PsdLayer)> textEdits = {
    'TySh': (layer) => layer.withTypeTool(
      PsdTypeTool.fromText(
        content: const PsdTextContent(text: 'New text', orientation: .horizontal),
      ),
    ),
    'tySh': (layer) => layer.withLegacyTypeTool(_legacyText()),
  };
  for (final MapEntry<String, PsdLayer Function(PsdLayer)> entry in textEdits.entries) {
    for (final bool exists in [false, true]) {
      test('${entry.key} ${exists ? 'replaces in place' : 'appends'} and removes conflicting text', () {
        final String obsolete = entry.key == 'TySh' ? 'tySh' : 'TySh';
        final PsdTaggedBlock first = PsdTaggedBlock(key: 'head', data: Uint8List.fromList([1]));
        final PsdTaggedBlock last = PsdTaggedBlock(key: 'tail', data: Uint8List.fromList([2]));
        final PsdLayer source = PsdLayer(
          rectangle: const .fromSize(width: 2, height: 3),
          name: 'Text',
          channels: [PsdChannel(id: 0, data: Uint8List(6))],
          opacity: 73,
          flags: 3,
          writesUnicodeName: false,
          additionalInfo: [
            first,
            PsdTaggedBlock(key: obsolete, data: Uint8List(0)),
            if (exists) PsdTaggedBlock(key: entry.key, data: Uint8List(0)),
            last,
            if (exists) PsdTaggedBlock(key: entry.key, data: Uint8List(0)),
          ],
        );

        final PsdLayer edited = entry.value(source);

        expect(edited.additionalInfo.map((block) => block.key), exists ? ['head', entry.key, 'tail'] : ['head', 'tail', entry.key]);
        expect(edited.additionalInfo.first, same(first));
        expect(edited.taggedBlock('tail'), same(last));
        expect(edited.rectangle, same(source.rectangle));
        expect(edited.channels, same(source.channels));
        expect(edited.opacity, 73);
        expect(edited.flags, 3);
        expect(edited.writesUnicodeName, isFalse);
        expect(source.taggedBlock(obsolete), isNotNull);
        if (entry.key == 'TySh') {
          expect(edited.typeTool?.text, 'New text');
        } else {
          expect(edited.legacyTypeTool?.characterCount, 0);
        }
      });
    }
  }

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

/// Creates a complete legacy record with no character or font entries.
PsdLegacyTypeTool _legacyText() => PsdLegacyTypeTool(
  faces: [],
  styles: [],
  type: 0,
  scalingFactor: 1,
  characterCount: 0,
  horizontalPlacement: 0,
  verticalPlacement: 0,
  selectionStart: 0,
  selectionEnd: 0,
  lines: [],
  color: PsdLegacyTextColor(colorSpace: 0, components: [0, 0, 0, 0]),
  antiAlias: true,
);
