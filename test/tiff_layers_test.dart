import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Exercises TIFF envelopes using both independently assembled and authored layers.
void main() {
  test('Reads an independent Intel-order layer with RLE row lengths', () {
    final Uint8List fixture = _intelFixture();
    final PsdTiffData data = PsdTiffCodec.decode(fixture);
    expect(data.byteOrder, Endian.little);
    expect(data.layers.single.name, 'X');
    expect(data.layers.single.channels.single.data, [20, 40]);
    expect(data.layers.single.blendingRanges, [0, 0, 255, 255, 0, 0, 255, 255]);
    expect(PsdTiffCodec.decode(PsdTiffCodec.encode(data)).layers.single.channels.single.data, [20, 40]);
  });

  for (final PsdVersion version in PsdVersion.values) {
    for (final int depth in [8, 16, 32]) {
      for (final Endian order in [Endian.big, Endian.little]) {
        test('${version.name} $depth-bit ${order == Endian.big ? 'MM' : 'II'} keeps samples and descriptors', () {
          final Uint8List samples = Uint8List.fromList(List.generate(2 * depth ~/ 8, (index) => 31 + index));
          final PsdTypeTool type = PsdTypeTool.fromText(
            content: const PsdTextContent(text: 'É😀', orientation: PsdTextOrientation.horizontal),
          );
          final PsdLayer layer = PsdLayer(
            rectangle: const PsdRectangle.fromSize(width: 2, height: 1),
            name: 'É😀',
            channels: [PsdChannel(id: 0, data: samples)],
            additionalInfo: [PsdTaggedBlock(key: 'TySh', data: PsdTypeToolCodec.encode(type))],
          );
          final PsdTiffData source = PsdTiffData(depth: depth, version: version, layers: [layer], mergedTransparency: true);
          final Uint8List bytes = PsdTiffCodec.encode(source, byteOrder: order);
          final PsdTiffData decoded = PsdTiffCodec.decode(bytes);
          expect(decoded.depth, depth);
          expect(decoded.version, version);
          expect(decoded.byteOrder, order);
          expect(decoded.mergedTransparency, isTrue);
          expect(decoded.layers.single.name, layer.name);
          expect(decoded.layers.single.channels.single.data, samples);
          expect(decoded.layers.single.typeTool!.text, type.text);
          expect(PsdTypeToolCodec.encode(decoded.layers.single.typeTool!), PsdTypeToolCodec.encode(type));
          expect(PsdTiffCodec.encode(decoded), bytes);
        });
      }
    }
  }

  test('Opaque Intel blocks survive their original order and cannot corrupt PSD output', () {
    final BytesBuilder builder = BytesBuilder()
      ..add('Adobe Photoshop Document Data Block\u0000'.codeUnits)
      ..add('MIB8zzzz'.codeUnits)
      ..add([3, 0, 0, 0, 9, 8, 7, 0]);
    final Uint8List bytes = builder.takeBytes();
    final PsdTiffData decoded = PsdTiffCodec.decode(bytes);
    expect(decoded.additionalLayerInfo.single.isForeignByteOrder, isTrue);
    expect(decoded.additionalLayerInfo.single.data, [9, 8, 7]);
    expect(PsdTiffCodec.encode(decoded), bytes);
    expect(() => PsdTiffCodec.encode(decoded, byteOrder: Endian.big), throwsA(isA<PsWriteException>()));
    final PsdDocument document = decoded.toDocument(width: 1, height: 1, channels: 1, colorMode: PsdColorMode.grayscale, mergedImage: [Uint8List(1)]);
    expect(() => PsdCodec.encode(document), throwsA(isA<PsWriteException>()));
  });

  test('Rejects malformed lengths before traversing nested records', () {
    final Uint8List bytes = _intelFixture();
    ByteData.sublistView(bytes).setUint32(44, 0xffffffff, Endian.little);
    expect(() => PsdTiffCodec.decode(bytes), throwsA(isA<PsFormatException>()));
  });

  test('Resource tag round-trips opaque ICC and numeric resource payloads', () {
    final List<PsdImageResource> resources = [
      PsdImageResource(id: 1039, name: 'ICC', data: Uint8List.fromList([9, 8, 7])),
    ];
    final Uint8List bytes = PsdTiffCodec.encodeResources(resources);
    final List<PsdImageResource> result = PsdTiffCodec.decodeResources(bytes);
    expect(result.single.name, 'ICC');
    expect(result.single.data, [9, 8, 7]);
  });
}

/// Assembles a Photoshop TIFF tag directly from the documented little-endian fields.
Uint8List _intelFixture() {
  final BytesBuilder layer = BytesBuilder();
  void integer(int value, int size) {
    final ByteData data = ByteData(size);
    if (size == 2) {
      data.setUint16(0, value, Endian.little);
    } else {
      data.setUint32(0, value, Endian.little);
    }
    layer.add(data.buffer.asUint8List());
  }

  integer(1, 2); // One layer.
  for (final int edge in [0, 0, 1, 2]) {
    integer(edge, 4);
  }
  integer(1, 2);
  integer(0, 2);
  integer(7, 4); // One channel, id 0, 7 encoded bytes.
  layer.add('MIB8mron'.codeUnits);
  layer.add([255, 0, 0, 0]);
  integer(20, 4); // Mask length + range length + ranges + Pascal name.
  integer(0, 4);
  integer(8, 4);
  layer.add([0, 0, 255, 255, 0, 0, 255, 255]);
  layer.add([1, 88, 0, 0]);
  integer(1, 2);
  integer(3, 2);
  layer.add([1, 20, 40]); // RLE: 3 bytes in the only row.
  final Uint8List payload = layer.takeBytes();
  final ByteData length = ByteData(4)..setUint32(0, payload.length, Endian.little);
  return (BytesBuilder()
        ..add('Adobe Photoshop Document Data Block\u0000MIB8ryaL'.codeUnits)
        ..add(length.buffer.asUint8List())
        ..add(payload)
        ..add(List.filled((4 - payload.length % 4) % 4, 0)))
      .takeBytes();
}
