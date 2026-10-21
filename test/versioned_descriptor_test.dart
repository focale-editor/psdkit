import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Exercises descriptor framing through each public metadata consumer.
void main() {
  final List<_DescriptorCase> cases = [
    (
      name: 'artboard',
      descriptor: PsdArtboard.create(left: 1, top: 2, right: 30, bottom: 40).descriptor,
      encode: (descriptor) => PsdArtboard(descriptor: descriptor).toBlock().data,
      decode: (bytes) => PsdArtboard.tryDecode(bytes)?.descriptor,
    ),
    (
      name: 'artboard defaults',
      descriptor: PsdArtboardDefaults.create(count: 2).descriptor,
      encode: (descriptor) => PsdArtboardDefaults(descriptor: descriptor).toBlock().data,
      decode: (bytes) => PsdArtboardDefaults.tryDecode(bytes)?.descriptor,
    ),
    (
      name: 'layer compositions',
      descriptor: PsdLayerCompLayerData.create(
        layerIdentifier: 7,
        originalEffectsReferencePoint: (horizontal: 0, vertical: 0),
        states: [],
      ).descriptor,
      encode: _encodeLayerComps,
      decode: _decodeLayerComps,
    ),
  ];
  for (final _DescriptorCase testCase in cases) {
    final PsDescriptor descriptor = testCase.descriptor.withValue('futureProperty', const PsStringValue(value: 'preserved'));
    final Uint8List body = PsDescriptorCodec.encode(descriptor);
    final Uint8List unpadded = Uint8List.fromList([0, 0, 0, 16, ...body]);

    test('${testCase.name} writes version 16, zero alignment and unknown properties', () {
      final Uint8List encoded = testCase.encode(descriptor);

      expect(encoded, [...unpadded, ...List<int>.filled((4 - unpadded.length % 4) % 4, 0)]);
      final PsDescriptor? decoded = testCase.decode(encoded);
      expect(decoded, isNotNull);
      expect(PsDescriptorCodec.encode(decoded!), body);
    });

    test('${testCase.name} accepts absent or extended zero padding', () {
      for (int padding = 0; padding <= 7; padding++) {
        final PsDescriptor? decoded = testCase.decode(Uint8List.fromList([...unpadded, ...List<int>.filled(padding, 0)]));

        expect(decoded, isNotNull, reason: '$padding padding bytes');
        expect(PsDescriptorCodec.encode(decoded!), body);
      }
    });

    test('${testCase.name} rejects unsupported versions, truncation and nonzero trailing data', () {
      final List<Uint8List> malformed = [
        Uint8List.fromList([0, 0, 0, 15, ...body]),
        Uint8List.fromList([0, 0, 0]),
        Uint8List.sublistView(unpadded, 0, unpadded.length - 1),
        Uint8List.fromList([...unpadded, 0, 0, 1]),
      ];

      for (final Uint8List bytes in malformed) {
        expect(testCase.decode(bytes), isNull);
      }
    });
  }
}

/// Supplies public encoding and decoding operations for one descriptor context.
typedef _DescriptorCase = ({
  String name,
  PsDescriptor descriptor,
  Uint8List Function(PsDescriptor) encode,
  PsDescriptor? Function(Uint8List) decode,
});

/// Extracts the descriptor payload written through the public composition API.
Uint8List _encodeLayerComps(PsDescriptor descriptor) {
  final PsdLayer layer = _layer().withLayerCompData(PsdLayerCompLayerData(descriptor: descriptor));
  final PsBinaryReader reader = PsBinaryReader(bytes: layer.taggedBlock('shmd')!.data);
  expect(reader.readUint32(), 1);
  expect(reader.readString(4), '8BIM');
  expect(reader.readString(4), 'cmls');
  reader.skip(4);
  return reader.readBytes(reader.readUint32());
}

/// Wraps a descriptor payload in a valid shared-metadata entry for public decoding.
PsDescriptor? _decodeLayerComps(Uint8List bytes) {
  final PsBinaryWriter writer = PsBinaryWriter()
    ..writeUint32(1)
    ..writeString('8BIM')
    ..writeString('cmls')
    ..writeZeros(4)
    ..writeUint32(bytes.length)
    ..writeBytes(bytes);
  if (bytes.length.isOdd) {
    writer.writeUint8(0);
  }
  return _layer(
    block: PsdTaggedBlock(key: 'shmd', data: writer.takeBytes()),
  ).layerCompData?.descriptor;
}

/// Hosts composition metadata without allocating raster data.
PsdLayer _layer({PsdTaggedBlock? block}) => PsdLayer(
  rectangle: const .fromSize(width: 1, height: 1),
  name: 'Metadata',
  additionalInfo: [?block],
);
