import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

import 'support/memory_output.dart';

/// Verifies shared metadata rules through both complete-document writers.
void main() {
  for (final PsdVersion version in PsdVersion.values) {
    for (final int depth in [8, 16, 32]) {
      final String key = switch (depth) {
        16 => 'Lr16',
        32 => 'Lr32',
        _ => 'Layr',
      };
      test('${version.name} $depth-bit replaces alternative layer blocks in place', () async {
        final PsdDocument document = _document(
          version: version,
          depth: depth,
          blocks: [
            _block('head'),
            _block('Lr32', signature: '8B64'),
            _block('midl'),
            _block(key),
            _block('Layr'),
            _block('tail'),
          ],
        );

        final PsdDocument decoded = await _expectWriterParity(document);

        expect(decoded.additionalLayerInfo.map((block) => block.key), ['head', key, 'midl', 'tail']);
        expect(decoded.additionalLayerInfo[1].signature, '8B64');
        expect(decoded.layers.single.channel(0)?.data, document.layers.single.channel(0)?.data);
        expect(decoded.layers.single.name, document.layers.single.name);
      });

      test('${version.name} $depth-bit removes stale blocks after deleting all layers', () async {
        final PsdDocument document = _document(
          version: version,
          depth: depth,
          withLayers: false,
          blocks: [
            _block('head'),
            _block(key),
            _block('tail'),
            _block(key),
          ],
        );

        final PsdDocument decoded = await _expectWriterParity(document);

        expect(decoded.layers, isEmpty);
        expect(decoded.additionalLayerInfo.map((block) => block.key), ['head', 'tail']);
      });

      test('${version.name} $depth-bit selects ordinary or alternate layer storage', () async {
        final PsdDocument document = _document(version: version, depth: depth, blocks: [_block('head')]);

        final PsdDocument decoded = await _expectWriterParity(document);

        expect(decoded.additionalLayerInfo.map((block) => block.key), ['head', if (depth != 8) key]);
        expect(decoded.layers.single.channel(0)?.data, document.layers.single.channel(0)?.data);
        expect(decoded.imageResources.map((resource) => resource.name), ['', 'A', 'AB']);
        expect(decoded.imageResources.map((resource) => resource.data), [
          [1],
          [2, 3],
          [4, 5, 6],
        ]);
        expect(decoded.imageResources.last.signature, '8B64');
      });
    }
  }

  for (final int depth in [8, 16]) {
    for (final bool withLayers in [false, true]) {
      test('$depth-bit streaming layer presence follows sources when metadata differs ($withLayers)', () async {
        final PsdDocument document = _document(depth: depth, withLayers: withLayers);
        final PsdStreamDocument source = PsdStreamDocument.fromDocument(document);
        final MemoryRandomAccessOutput output = MemoryRandomAccessOutput();

        await PsdCodec.encodeTo(
          PsdStreamDocument(
            metadata: _document(depth: depth, withLayers: !withLayers),
            layers: source.layers,
            mergedImage: source.mergedImage,
          ),
          output,
        );

        expect(output.bytes, orderedEquals(PsdCodec.encode(document)));
        expect(PsdCodec.decode(output.bytes).layers.length, withLayers ? 1 : 0);
      });
    }
  }

  final Map<String, PsdDocument> invalidMetadata = {
    'resource signature': _document(
      resources: [PsdImageResource(id: 1, signature: 'bad', data: Uint8List(0))],
    ),
    'negative resource id': _document(resources: [PsdImageResource(id: -1, data: Uint8List(0))]),
    'oversized resource id': _document(resources: [PsdImageResource(id: 65536, data: Uint8List(0))]),
    'blend mode': _document(layer: _layer(blendMode: 'bad')),
    'opacity': _document(layer: _layer(opacity: 256)),
    'clipping': _document(layer: _layer(clipping: -1)),
    'flags': _document(layer: _layer(flags: 256)),
  };
  for (final MapEntry<String, PsdDocument> entry in invalidMetadata.entries) {
    test('both writers reject invalid ${entry.key}', () async {
      expect(() => PsdCodec.encode(entry.value), throwsA(isA<PsWriteException>()));
      await expectLater(
        PsdCodec.encodeTo(PsdStreamDocument.fromDocument(entry.value), MemoryRandomAccessOutput()),
        throwsA(isA<PsWriteException>()),
      );
    });
  }
}

/// Compares complete encoded bytes, then decodes the progressive result.
Future<PsdDocument> _expectWriterParity(PsdDocument document) async {
  final MemoryRandomAccessOutput output = MemoryRandomAccessOutput();
  final int length = await PsdCodec.encodeTo(PsdStreamDocument.fromDocument(document), output, rowBatchSize: 1);
  expect(length, output.bytes.length);
  expect(output.bytes, orderedEquals(PsdCodec.encode(document)));
  final PsdDocument decoded = PsdCodec.decode(output.bytes);
  expect(decoded.version, document.version);
  expect(decoded.depth, document.depth);
  expect(decoded.mergedImage.single, document.mergedImage.single);
  expect(decoded.globalLayerMaskData, document.globalLayerMaskData);
  return decoded;
}

/// Builds metadata with odd and even resource names and payload sizes.
PsdDocument _document({
  PsdVersion version = .psd,
  int depth = 8,
  bool withLayers = true,
  List<PsdTaggedBlock> blocks = const [],
  List<PsdImageResource>? resources,
  PsdLayer? layer,
}) => PsdDocument(
  version: version,
  width: 2,
  height: 1,
  channels: 1,
  depth: depth,
  colorMode: .grayscale,
  imageResources:
      resources ??
      [
        PsdImageResource(id: 3000, data: Uint8List.fromList([1])),
        PsdImageResource(id: 3001, name: 'A', data: Uint8List.fromList([2, 3])),
        PsdImageResource(id: 3002, name: 'AB', signature: '8B64', data: Uint8List.fromList([4, 5, 6])),
      ],
  layers: [if (withLayers) layer ?? _layer(depth: depth)],
  mergedImage: [_samples(depth)],
  mergedImageCompression: .raw,
  globalLayerMaskData: Uint8List.fromList([7, 8]),
  additionalLayerInfo: blocks,
);

/// Builds a layer whose metadata can be varied independently of valid pixels.
PsdLayer _layer({int depth = 8, String blendMode = 'norm', int opacity = 127, int clipping = 1, int flags = 2}) => PsdLayer(
  rectangle: const .fromSize(width: 2, height: 1),
  name: 'Calque é',
  channels: [PsdChannel(id: 0, data: _samples(depth), compression: .raw)],
  blendMode: blendMode,
  opacity: opacity,
  clipping: clipping,
  flags: flags,
  additionalInfo: [_block('test')],
);

/// Supplies two samples with distinct bytes at the requested depth.
Uint8List _samples(int depth) => Uint8List.fromList([for (int index = 0; index < depth ~/ 4; index++) index * 17]);

/// Creates an opaque payload whose bytes must survive unrelated edits.
PsdTaggedBlock _block(String key, {String signature = '8BIM'}) => PsdTaggedBlock(key: key, signature: signature, data: Uint8List.fromList([9, 10]));
