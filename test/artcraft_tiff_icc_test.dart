@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Exercises independent layered TIFFs and real ICC resource payloads.
void main() {
  const String tiffRoot = 'test/fixtures/layered_tiff';
  for (final Map<String, dynamic> entry in _entries(tiffRoot)) {
    final String path = entry['path'] as String;
    test('Independent layered TIFF $path preserves every layer sample', () {
      final Uint8List file = _verified(tiffRoot, entry);
      final Uint8List payload = _imageSourceData(file);
      expect(sha256.convert(payload).toString(), entry['imageSourceDataSha256']);
      final PsdTiffData source = PsdTiffCodec.decode(payload);
      expect(source.byteOrder, entry['byteOrder'] == 'little' ? Endian.little : Endian.big);
      expect(source.depth, entry['depth']);
      _expectLayers(source);
      for (final Endian order in [Endian.big, Endian.little]) {
        final PsdTiffData restored = PsdTiffCodec.decode(PsdTiffCodec.encode(source, byteOrder: order));
        expect(restored.byteOrder, order);
        expect(restored.depth, source.depth);
        expect(restored.globalLayerMaskData, source.globalLayerMaskData);
        expect(restored.additionalLayerInfo.map((block) => [block.key, block.data]), source.additionalLayerInfo.map((block) => [block.key, block.data]));
        _expectLayers(restored);
      }
    });
  }

  const String iccRoot = 'test/fixtures/artcraft_icc';
  for (final Map<String, dynamic> entry in _entries(iccRoot)) {
    test('Real ICC ${entry['path']} survives PSD, PSB and TIFF resources', () {
      final Uint8List bytes = _verified(iccRoot, entry);
      final PsdIccProfileResource profile = PsdImageResourceCodec.decode(bytes, resourceId: PsdImageResourceIds.iccProfile) as PsdIccProfileResource;
      expect(profile.hasValidSignature, isTrue);
      expect(profile.declaredSize, bytes.length);
      expect(profile.colorSpace?.trim(), entry['colorSpace']);
      expect(profile.version! >> 24, entry['majorVersion']);
      expect(PsdImageResourceCodec.encode(profile), bytes);
      final PsdImageResource resource = PsdImageResource(id: PsdImageResourceIds.iccProfile, name: 'ICC', data: bytes);
      final PsdColorMode mode = switch (entry['colorSpace']) {
        'CMYK' => PsdColorMode.cmyk,
        'GRAY' => PsdColorMode.grayscale,
        _ => PsdColorMode.rgb,
      };
      final int channels = mode == PsdColorMode.cmyk ? 4 : (mode == PsdColorMode.grayscale ? 1 : 3);
      for (final PsdVersion version in PsdVersion.values) {
        final PsdDocument document = PsdDocument(
          version: version,
          width: 1,
          height: 1,
          depth: 8,
          channels: channels,
          colorMode: mode,
          mergedImage: List.generate(channels, (_) => Uint8List(1)),
          imageResources: [resource],
        );
        final PsdDocument restored = PsdCodec.decode(PsdCodec.encode(document));
        expect(restored.imageResources.single.data, bytes);
        expect(restored.imageResources.single.id, PsdImageResourceIds.iccProfile);
      }
      expect(PsdTiffCodec.decodeResources(PsdTiffCodec.encodeResources([resource])).single.data, bytes);
    });
  }
}

/// Loads committed fixture identities without fetching data during tests.
List<Map<String, dynamic>> _entries(String root) => ((jsonDecode(File('$root/manifest.json').readAsStringSync()) as Map<String, dynamic>)['files'] as List<dynamic>).cast<Map<String, dynamic>>();

/// Refuses silently replaced or truncated reference files.
Uint8List _verified(String root, Map<String, dynamic> entry) {
  final Uint8List bytes = File('$root/${entry['path']}').readAsBytesSync();
  expect(bytes.length, entry['size']);
  expect(sha256.convert(bytes).toString(), entry['sha256']);
  return bytes;
}

/// Extracts one opaque TIFF tag without depending on a sibling raster codec.
Uint8List _imageSourceData(Uint8List bytes) {
  final ByteData data = ByteData.sublistView(bytes);
  final Endian order = bytes[0] == 0x49 ? Endian.little : Endian.big;
  expect(data.getUint16(2, order), 42);
  final int directory = data.getUint32(4, order);
  final int count = data.getUint16(directory, order);
  for (int index = 0; index < count; index++) {
    final int offset = directory + 2 + index * 12;
    if (data.getUint16(offset, order) == 37724) {
      expect(data.getUint16(offset + 2, order), 7); // TIFF UNDEFINED bytes.
      final int length = data.getUint32(offset + 4, order);
      final int start = data.getUint32(offset + 8, order);
      return Uint8List.sublistView(bytes, start, start + length);
    }
  }
  throw StateError('Missing Photoshop ImageSourceData');
}

/// Checks the independent generator's ramps, bounds, names and blend settings.
void _expectLayers(PsdTiffData data) {
  expect(data.layers.map((layer) => layer.name), ['Background', 'Upper é']);
  expect(data.layers.map((layer) => layer.blendMode), ['norm', 'mul ']);
  expect(data.layers.map((layer) => layer.opacity), [255, 200]);
  for (int index = 0; index < 2; index++) {
    final PsdLayer layer = data.layers[index];
    final int width = index == 0 ? 6 : 4;
    final int height = index == 0 ? 4 : 3;
    final int seed = index == 0 ? 1 : 7;
    expect((layer.rectangle.left, layer.rectangle.top, layer.rectangle.width, layer.rectangle.height), (index, index, width, height));
    expect(layer.channels.map((channel) => channel.id), [-1, 0, 1, 2]);
    for (final PsdChannel channel in layer.channels) {
      final ByteData pixels = ByteData.sublistView(channel.data);
      expect(channel.data.length, width * height * data.depth ~/ 8);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int expected = switch (channel.id) {
            -1 => index == 0 ? 255 : x * 80 % 256,
            0 => (x * 40 + seed) % 256,
            1 => (y * 60 + seed * 3) % 256,
            _ => (x * y * 17 + seed) % 256,
          };
          final int offset = (y * width + x) * data.depth ~/ 8;
          expect(data.depth == 8 ? pixels.getUint8(offset) : pixels.getUint16(offset), expected * (data.depth == 8 ? 1 : 257));
        }
      }
    }
  }
}
