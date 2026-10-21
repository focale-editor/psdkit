@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

import 'support/memory_output.dart';

/// Verifies external PSD/PSB samples against psd-tools and both read paths.
void main() {
  const String root = 'test/corpus/artcraft';
  final Map<String, dynamic> manifest = jsonDecode(File('$root/manifest.json').readAsStringSync()) as Map<String, dynamic>;
  final Map<String, dynamic> reference = (jsonDecode(File('$root/reference.json').readAsStringSync()) as Map<String, dynamic>)['files'] as Map<String, dynamic>;
  test('Selected fixtures are unique across both corpus manifests', () {
    final Map<String, dynamic> photocraft = jsonDecode(File('test/corpus/photocraft/manifest.json').readAsStringSync()) as Map<String, dynamic>;
    final List<Map<String, dynamic>> entries = [
      ...(manifest['files'] as List<dynamic>).cast<Map<String, dynamic>>(),
      ...(photocraft['files'] as List<dynamic>).cast<Map<String, dynamic>>().where((entry) => (entry['path'] as String).endsWith('.psd')),
    ];
    expect(entries.map((entry) => entry['sha256']).toSet().length, entries.length);
  });
  for (final Map<String, dynamic> entry in (manifest['files'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    final String path = entry['path'] as String;
    test('ArtCraft $path', () {
      final Uint8List bytes = File('$root/$path').readAsBytesSync();
      final String digest = sha256.convert(bytes).toString();
      expect(bytes.length, entry['size']);
      expect(digest, entry['sha256']);
      final Map<String, dynamic> header = entry['header'] as Map<String, dynamic>;
      final Map<String, dynamic> oracle = reference[path] as Map<String, dynamic>;
      final PsdDocument document = PsdCodec.decode(bytes);
      expect(document.version.code, header['version']);
      expect(document.width, header['width']);
      expect(document.height, header['height']);
      expect(document.channels, header['channels']);
      expect(document.depth, header['depth']);
      expect(document.colorMode.code, header['colorMode']);
      expect(document.warnings, isEmpty);
      expect(document.mergedImage.map((plane) => sha256.convert(plane).toString()), oracle['mergedSha256']);
      final List<Map<String, dynamic>> layers = (oracle['layers'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(document.layers.length, layers.length);
      for (int index = 0; index < layers.length; index++) {
        final PsdLayer layer = document.layers[index];
        final Map<String, dynamic> expected = layers[index];
        expect(layer.name, expected['name']);
        expect(_rectangle(layer.rectangle), expected['rectangle']);
        expect(layer.opacity, expected['opacity']);
        expect(layer.blendMode, expected['blendMode']);
        expect(layer.flags, expected['flags']);
        expect(layer.clipping, expected['clipping']);
        final List<Map<String, dynamic>> channels = (expected['channels'] as List<dynamic>).cast<Map<String, dynamic>>();
        expect(layer.channels.map((channel) => channel.id), channels.map((channel) => channel['id']));
        for (int channel = 0; channel < channels.length; channel++) {
          if (channels[channel]['sha256'] case final String hash) {
            expect(sha256.convert(layer.channels[channel].data).toString(), hash, reason: 'Layer $index channel $channel');
          }
        }
      }
      final PsdDocument lazy = PsdCodec.decode(bytes, options: const PsdReadOptions(lazyPixels: true));
      _expectSameDocument(lazy, document);
      final PsdDocument restored = PsdCodec.decode(PsdCodec.encode(document, options: const PsdWriteOptions(compatibility: PsdWriteCompatibility.preserve)));
      _expectSameDocument(restored, document);
    });
  }

  test('Real PSB cinf uses wide lengths in progressive and TIFF writers', () async {
    final PsdDocument source = PsdCodec.decode(File('$root/ag-psd/read-write/psb2/src.psb').readAsBytesSync());
    final PsdTaggedBlock compositor = source.additionalLayerInfo.singleWhere((block) => block.key == 'cinf');
    expect(compositor.signature, '8B64');
    expect(compositor.data.length, 502);
    final MemoryRandomAccessOutput output = MemoryRandomAccessOutput();
    await PsdCodec.encodeTo(PsdStreamDocument.fromDocument(source), output);
    _expectSameDocument(PsdCodec.decode(output.bytes), source);
    for (final Endian order in [Endian.big, Endian.little]) {
      final PsdTiffData restored = PsdTiffCodec.decode(PsdTiffCodec.encode(PsdTiffData.fromDocument(source), byteOrder: order));
      expect(restored.additionalLayerInfo.singleWhere((block) => block.key == 'cinf').data, compositor.data);
      expect(restored.layers.map((layer) => layer.channels.map((channel) => channel.data)), source.layers.map((layer) => layer.channels.map((channel) => channel.data)));
    }
  });
}

/// Orders bounds like the independent psd-tools oracle.
List<int> _rectangle(PsdRectangle rectangle) => [rectangle.top, rectangle.left, rectangle.bottom, rectangle.right];

/// Compares decoded pixels and opaque data without relying on encoder byte layout.
void _expectSameDocument(PsdDocument actual, PsdDocument expected) {
  expect(
    (actual.version, actual.width, actual.height, actual.channels, actual.depth, actual.colorMode),
    (expected.version, expected.width, expected.height, expected.channels, expected.depth, expected.colorMode),
  );
  expect(actual.mergedImage, expected.mergedImage);
  expect(actual.colorModeData, expected.colorModeData);
  expect(actual.mergedTransparency, expected.mergedTransparency);
  expect(actual.globalLayerMaskData, expected.globalLayerMaskData);
  expect(actual.imageResources.map((resource) => [resource.id, resource.name, resource.data]), expected.imageResources.map((resource) => [resource.id, resource.name, resource.data]));
  expect(actual.layers.length, expected.layers.length);
  for (int index = 0; index < expected.layers.length; index++) {
    final PsdLayer source = expected.layers[index];
    final PsdLayer result = actual.layers[index];
    expect(_rectangle(result.rectangle), _rectangle(source.rectangle));
    expect((result.name, result.blendMode, result.opacity, result.flags, result.clipping), (source.name, source.blendMode, source.opacity, source.flags, source.clipping));
    expect(result.blendingRanges, source.blendingRanges);
    expect(result.mask?.data, source.mask?.data);
    expect(result.mask == null ? null : _rectangle(result.mask!.rectangle), source.mask == null ? null : _rectangle(source.mask!.rectangle));
    expect(result.mask?.realRectangle == null ? null : _rectangle(result.mask!.realRectangle!), source.mask?.realRectangle == null ? null : _rectangle(source.mask!.realRectangle!));
    expect(result.channels.map((channel) => [channel.id, channel.data]), source.channels.map((channel) => [channel.id, channel.data]));
    for (final PsdTaggedBlock block in source.additionalInfo) {
      expect(result.additionalInfo.where((candidate) => candidate.key == block.key).map((candidate) => candidate.data), contains(orderedEquals(block.data)));
    }
  }
  // Layer-info blocks are regenerated from the decoded layers by the writer.
  for (final PsdTaggedBlock block in expected.additionalLayerInfo.where((block) => !const {'Layr', 'Lr16', 'Lr32'}.contains(block.key))) {
    expect(actual.additionalLayerInfo.where((candidate) => candidate.key == block.key).map((candidate) => candidate.data), contains(orderedEquals(block.data)));
  }
}
