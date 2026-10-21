@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

import 'support/memory_output.dart';

/// Checks immutable upstream evidence and exercises both writer paths.
void main() {
  final Map<String, dynamic> manifest = jsonDecode(File('test/corpus/photocraft/manifest.json').readAsStringSync()) as Map<String, dynamic>;
  for (final Map<String, dynamic> entry in (manifest['files'] as List<dynamic>).cast<Map<String, dynamic>>()) {
    final String path = entry['path'] as String;
    test('Photocraft $path', () {
      final Uint8List bytes = File('test/corpus/photocraft/$path').readAsBytesSync();
      expect(bytes.length, entry['size']);
      expect(sha256.convert(bytes).toString(), entry['sha256']);
      if (!path.endsWith('.psd')) {
        return;
      }
      final PsdDocument source = PsdCodec.decode(bytes);
      final PsdDocument result = PsdCodec.decode(PsdCodec.encode(source));
      expect((result.width, result.height, result.depth, result.colorMode), (source.width, source.height, source.depth, source.colorMode));
      expect(result.mergedImage, source.mergedImage);
      expect(result.layers.length, source.layers.length);
      for (final Endian order in [Endian.big, Endian.little]) {
        final PsdTiffData tiff = PsdTiffCodec.decode(PsdTiffCodec.encode(PsdTiffData.fromDocument(source), byteOrder: order));
        expect(tiff.layers.length, source.layers.length);
        for (int i = 0; i < source.layers.length; i++) {
          expect(tiff.layers[i].name, source.layers[i].name);
          expect(tiff.layers[i].channels.map((value) => value.data), source.layers[i].channels.map((value) => value.data));
          for (final PsdTaggedBlock block in source.layers[i].additionalInfo) {
            expect(tiff.layers[i].additionalInfo.where((value) => value.key == block.key).map((value) => value.data), contains(orderedEquals(block.data)));
          }
        }
      }

      expect(result.imageResources.map((value) => (value.id, value.name)), source.imageResources.map((value) => (value.id, value.name)));
      expect(result.imageResources.map((value) => value.data), source.imageResources.map((value) => value.data));
      for (int i = 0; i < source.layers.length; i++) {
        expect(result.layers[i].name, source.layers[i].name);
        expect(result.layers[i].channels.map((value) => value.id), source.layers[i].channels.map((value) => value.id));
        expect(result.layers[i].channels.map((value) => value.data), source.layers[i].channels.map((value) => value.data));
        for (final PsdTaggedBlock block in source.layers[i].additionalInfo) {
          expect(result.layers[i].additionalInfo.where((value) => value.key == block.key).map((value) => value.data), contains(orderedEquals(block.data)));
        }
      }
    });
  }

  test('Both 32-bit writers emit Photoshop HDR records and avoid RLE', () async {
    final PsdDocument document = _document(depth: 32);
    final Uint8List bytes = PsdCodec.encode(document);
    final PsdDocument decoded = PsdCodec.decode(bytes);
    final PsdDocument oracle = PsdCodec.decode(File('test/corpus/photocraft/photoshop/adjustments/rgb32/baseline-layer-copy.psd').readAsBytesSync());
    expect(decoded.colorModeData, oracle.colorModeData);
    expect(decoded.colorModeData.length, 110);
    expect(decoded.mergedImageCompression, PsdCompression.raw);
    expect(decoded.layers.single.channels.single.compression, PsdCompression.raw);
    final MemoryRandomAccessOutput output = MemoryRandomAccessOutput();
    await PsdCodec.encodeTo(PsdStreamDocument.fromDocument(document), output);
    expect(output.bytes, bytes);
    final PsdDocument preserved = PsdCodec.decode(PsdCodec.encode(document, options: const PsdWriteOptions(compatibility: PsdWriteCompatibility.preserve)));
    expect(preserved.colorModeData, isEmpty);
    expect(preserved.mergedImageCompression, PsdCompression.rle);
    expect(preserved.layers.single.channels.single.compression, PsdCompression.rle);
  });

  test('Deferred planes decode once and respect the aggregate budget', () {
    final Uint8List bytes = PsdCodec.encode(_document());
    final PsdDocument document = PsdCodec.decode(bytes, options: const PsdReadOptions(lazyPixels: true, maxTotalDecodedBytes: 4));
    final PsdChannel channel = document.layers.single.channels.single;
    expect(channel.isDecoded, isFalse);
    expect(channel.data, [1, 2, 3, 4]);
    expect(channel.isDecoded, isTrue);
    expect(identical(channel.data, channel.data), isTrue);
    expect(() => document.mergedImage.first, throwsA(isA<PsFormatException>()));
    expect(() => PsdCodec.decode(bytes, options: const PsdReadOptions(maxTotalDecodedBytes: 7)), throwsA(isA<PsFormatException>()));
    expect(PsdCodec.decode(bytes, options: const PsdReadOptions(maxTotalDecodedBytes: 8)).mergedImage.single, [1, 2, 3, 4]);
  });

  test('Only the selected layer-info section consumes the decoded budget', () {
    final Uint8List original = PsdCodec.encode(_document());
    final PsBinaryReader reader = PsBinaryReader(bytes: original)..skip(26);
    reader.skip(reader.readUint32());
    reader.skip(reader.readUint32());
    final int sectionOffset = reader.offset;
    final PsBinaryReader section = reader.readReader(reader.readUint32());
    final Uint8List layerInfo = section.readBytes(section.readUint32());
    final PsBinaryWriter replacement = PsBinaryWriter()
      ..writeUint32(layerInfo.length)
      ..writeBytes(layerInfo)
      ..writeUint32(0)
      ..writeString('8BIMLayr')
      ..writeUint32(layerInfo.length)
      ..writeBytes(layerInfo);
    final Uint8List payload = replacement.takeBytes();
    final Uint8List bytes =
        (PsBinaryWriter()
              ..writeBytes(Uint8List.sublistView(original, 0, sectionOffset))
              ..writeUint32(payload.length)
              ..writeBytes(payload)
              ..writeBytes(reader.readBytes(reader.remaining)))
            .takeBytes();
    final PsdDocument result = PsdCodec.decode(bytes, options: const PsdReadOptions(maxTotalDecodedBytes: 8));
    expect(result.layers.single.channels.single.data, [1, 2, 3, 4]);
    expect(result.mergedImage.single, [1, 2, 3, 4]);
  });

  test('Damaged merged data can be recovered without hiding allocation failures', () {
    final Uint8List bytes = PsdCodec.encode(_document(), options: const PsdWriteOptions(compression: PsdCompression.raw));
    final Uint8List damaged = Uint8List.sublistView(bytes, 0, bytes.length - 3);
    expect(() => PsdCodec.decode(damaged), throwsA(isA<PsFormatException>()));
    for (final bool lazy in [false, true]) {
      final PsdDocument recovered = PsdCodec.decode(damaged, options: PsdReadOptions(lazyPixels: lazy, recoverMergedImage: true));
      expect(recovered.layers.single.channels.single.data, [1, 2, 3, 4]);
      expect(recovered.mergedImage, isEmpty);
      expect(recovered.warnings, hasLength(1));
      expect(() => PsdCodec.encode(recovered), throwsA(isA<PsWriteException>()));
    }
    expect(() => PsdCodec.decode(damaged, options: const PsdReadOptions(recoverMergedImage: true, maxTotalDecodedBytes: 4)), throwsA(isA<PsFormatException>()));
    final PsdDocument flat = _document(layers: false);
    final Uint8List flatBytes = PsdCodec.encode(flat);
    expect(() => PsdCodec.decode(Uint8List.sublistView(flatBytes, 0, flatBytes.length - 3), options: const PsdReadOptions(recoverMergedImage: true)), throwsA(isA<PsFormatException>()));
  });
}

/// Builds a small grayscale source with one independent layer plane.
PsdDocument _document({int depth = 8, bool layers = true}) {
  final Uint8List samples = depth == 8
      ? Uint8List.fromList([1, 2, 3, 4])
      : (ByteData(16)
              ..setFloat32(0, 0.25)
              ..setFloat32(4, 0.5)
              ..setFloat32(8, 1)
              ..setFloat32(12, 2))
            .buffer
            .asUint8List();
  return PsdDocument(
    width: 2,
    height: 2,
    channels: 1,
    depth: depth,
    colorMode: PsdColorMode.grayscale,
    mergedImage: [samples],
    layers: [
      if (layers)
        PsdLayer(
          rectangle: const PsdRectangle.fromSize(width: 2, height: 2),
          name: 'Plane',
          channels: [PsdChannel(id: 0, data: samples)],
        ),
    ],
  );
}
