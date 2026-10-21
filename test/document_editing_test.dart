import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Checks metadata edits without copying pixels or losing document settings.
void main() {
  final List<_DocumentEditCase> cases = [
    (
      name: 'artboard defaults',
      keys: ['artd', 'artd'],
      resultKeys: ['head', 'tail', 'artd'],
      edit: (document) => document.withArtboardDefaults(PsdArtboardDefaults.create(count: 2)),
    ),
    (name: 'remove artboard defaults', keys: ['artd'], resultKeys: ['head', 'tail'], edit: (document) => document.withArtboardDefaults(null)),
    (name: 'remove patterns', keys: ['Patt', 'Pat2', 'Pat3'], resultKeys: ['head', 'tail'], edit: (document) => document.withPatterns([])),
    (
      name: 'global text',
      keys: ['Txt2', 'Txt2'],
      resultKeys: ['head', 'tail', 'Txt2'],
      edit: (document) => document.withGlobalTextEngineData(PsdGlobalTextEngineData(data: Uint8List.fromList([1, 2]))),
    ),
    (name: 'remove global text', keys: ['Txt2'], resultKeys: ['head', 'tail'], edit: (document) => document.withGlobalTextEngineData(null)),
    (
      name: 'filter caches',
      keys: ['FEid', 'FXid'],
      resultKeys: ['head', 'tail', 'FEid'],
      edit: (document) => document.withFilterEffects(PsdFilterEffects(effects: [])),
    ),
    (
      name: 'linked resources',
      keys: ['lnkD', 'lnk2', 'lnk3'],
      resultKeys: ['head', 'tail', 'lnk2'],
      edit: (document) => document.withLinkedResourceBlocks([PsdLinkedResourceBlock(entries: [])]),
    ),
    (name: 'remove linked resources', keys: ['lnk2'], resultKeys: ['head', 'tail'], edit: (document) => document.withLinkedResources([])),
  ];
  for (final _DocumentEditCase testCase in cases) {
    test('${testCase.name} preserves document settings and unrelated blocks', () {
      final PsdDocument source = _document(testCase.keys);

      final PsdDocument edited = testCase.edit(source);

      _expectDocumentSettings(edited, source);
      expect(edited.imageResources, same(source.imageResources));
      expect(edited.additionalLayerInfo.map((block) => block.key), testCase.resultKeys);
      expect(edited.additionalLayerInfo[0], same(source.additionalLayerInfo.first));
      expect(edited.additionalLayerInfo[1], same(source.additionalLayerInfo.last));
      expect(source.additionalLayerInfo.map((block) => block.key), ['head', ...testCase.keys, 'tail']);
    });
  }

  test('named paths preserve other resources and document settings', () {
    final PsdDocument source = _document(['keep']);

    final PsdDocument edited = source.withNamedPaths([
      PsdNamedPath(
        resourceId: 2001,
        name: 'New path',
        path: PsdVectorPath.fromSubpaths(subpaths: []),
      ),
    ]);

    _expectDocumentSettings(edited, source);
    expect(edited.additionalLayerInfo, same(source.additionalLayerInfo));
    expect(edited.imageResources.map((resource) => resource.id), [1000, 1060, 1060, 1001, 2001]);
    expect(edited.imageResources.first, same(source.imageResources.first));
    expect(edited.namedPaths.single.name, 'New path');
  });

  test('resource replacement keeps the first matching header and removes duplicates', () {
    final PsdDocument source = _document(['keep']);

    final PsdDocument edited = source.withImageResourceData(PsdTextImageResource(resourceId: 1060, value: 'updated', utf8: true));

    _expectDocumentSettings(edited, source);
    expect(edited.additionalLayerInfo, same(source.additionalLayerInfo));
    expect(edited.imageResources.map((resource) => resource.id), [1000, 2000, 1060, 2002, 1001]);
    expect(edited.imageResource(1060)?.name, 'Resource 2');
    expect(edited.imageResource(1060)?.signature, '8B64');
    expect((edited.decodedImageResource(1060)! as PsdTextImageResource).value, 'updated');
  });

  test('resource removal preserves document settings and all other resources', () {
    final PsdDocument source = _document(['keep']);

    final PsdDocument edited = source.withoutImageResource(1060);

    _expectDocumentSettings(edited, source);
    expect(edited.additionalLayerInfo, same(source.additionalLayerInfo));
    expect(edited.imageResources.map((resource) => resource.id), [1000, 2000, 2002, 1001]);
    expect(source.imageResources, hasLength(6));
  });
}

/// An edit with its obsolete tagged blocks and resulting block order.
typedef _DocumentEditCase = ({String name, List<String> keys, List<String> resultKeys, PsdDocument Function(PsdDocument) edit});

/// Creates a document with nondefault metadata and duplicate opaque resources.
PsdDocument _document(List<String> keys) {
  const List<int> resourceIds = [1000, 2000, 1060, 2002, 1060, 1001];
  return PsdDocument(
    version: .psb,
    width: 2,
    height: 3,
    channels: 1,
    depth: 16,
    colorMode: .grayscale,
    colorModeData: Uint8List.fromList([3, 4]),
    mergedImageCompression: .zip,
    mergedTransparency: true,
    mergedImage: [Uint8List(12)],
    layers: [PsdLayer(rectangle: const .fromSize(width: 2, height: 3), name: 'Preserved')],
    globalLayerMaskData: Uint8List.fromList([5, 6]),
    additionalLayerInfo: [
      PsdTaggedBlock(key: 'head', data: Uint8List.fromList([10])),
      for (final String key in keys) PsdTaggedBlock(key: key, data: Uint8List(0)),
      PsdTaggedBlock(key: 'tail', data: Uint8List.fromList([20])),
    ],
    imageResources: [
      for (int index = 0; index < resourceIds.length; index++) PsdImageResource(id: resourceIds[index], name: 'Resource $index', signature: '8B64', data: Uint8List(0)),
    ],
  );
}

/// Verifies fields unrelated to the two editable metadata collections.
void _expectDocumentSettings(PsdDocument actual, PsdDocument source) {
  expect(actual, isNot(same(source)));
  expect(actual.version, source.version);
  expect(actual.width, source.width);
  expect(actual.height, source.height);
  expect(actual.channels, source.channels);
  expect(actual.depth, source.depth);
  expect(actual.colorMode, source.colorMode);
  expect(actual.colorModeData, same(source.colorModeData));
  expect(actual.layers, same(source.layers));
  expect(actual.mergedImage, same(source.mergedImage));
  expect(actual.mergedImageCompression, source.mergedImageCompression);
  expect(actual.mergedTransparency, source.mergedTransparency);
  expect(actual.globalLayerMaskData, same(source.globalLayerMaskData));
}
