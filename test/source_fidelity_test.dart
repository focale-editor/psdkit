import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Files written by other applications than Photoshop round-trip unchanged.
void main() {
  /// Explicitly opts into source retention for fidelity regressions.
  PsdDocument decode(Uint8List bytes) => PsdCodec.decode(bytes, options: const PsdReadOptions(preserveSourceEncoding: true));

  /// A one-layer, one-pixel RGB document.
  PsdDocument document(PsdLayer layer) => PsdDocument(
    width: 1,
    height: 1,
    channels: 3,
    depth: 8,
    colorMode: PsdColorMode.rgb,
    layers: [layer],
    mergedImage: [
      for (int index = 0; index < 3; index++) Uint8List.fromList([0]),
    ],
  );

  /// A one-pixel layer named [name].
  PsdLayer layer(String name, {bool writesUnicodeName = true}) => PsdLayer(
    rectangle: const PsdRectangle(top: 0, left: 0, bottom: 1, right: 1),
    name: name,
    channels: [
      for (final int id in [-1, 0, 1, 2]) PsdChannel(id: id, data: Uint8List.fromList([200])),
    ],
    writesUnicodeName: writesUnicodeName,
  );

  test('a layer read without a Unicode name is written without one', () {
    final Uint8List bytes = PsdCodec.encode(document(layer('Layer 1', writesUnicodeName: false)));
    final PsdDocument decoded = decode(bytes);

    expect(decoded.layers.single.name, 'Layer 1');
    expect(decoded.layers.single.writesUnicodeName, isFalse);
    expect(decoded.layers.single.additionalInfo.map((block) => block.key), isNot(contains('luni')));
    expect(PsdCodec.encode(decoded), bytes);
  });

  test('a name the Pascal field cannot hold still gets a Unicode block', () {
    final PsdDocument decoded = decode(PsdCodec.encode(document(layer('Calque é', writesUnicodeName: false))));

    expect(decoded.layers.single.name, 'Calque é');
  });

  test('a renamed layer has its Unicode block replaced in place', () {
    final PsdLayer source = decode(PsdCodec.encode(document(layer('Before')))).layers.single;
    final PsdLayer renamed = PsdLayer(
      rectangle: source.rectangle,
      name: 'After',
      channels: source.channels,
      additionalInfo: [
        PsdTaggedBlock(key: 'lnsr', data: Uint8List(4)),
        ...source.additionalInfo,
      ],
    );

    final PsdLayer decoded = decode(PsdCodec.encode(document(renamed))).layers.single;

    expect(decoded.name, 'After');
    expect(decoded.additionalInfo.map((block) => block.key), ['lnsr', 'luni']);
  });

  test('layer info aligned to four bytes keeps its padding', () {
    // Pad the layer info to a multiple of four, as some writers do.
    final Uint8List source = PsdCodec.encode(document(layer('Layer 1')));
    final ByteData view = ByteData.sublistView(source);
    final int colorModeEnd = 26 + 4 + view.getUint32(26);
    final int sectionStart = colorModeEnd + 4 + view.getUint32(colorModeEnd);
    final int layerInfoLength = view.getUint32(sectionStart + 4);
    final int padding = (4 - layerInfoLength % 4) % 4 == 0 ? 4 : (4 - layerInfoLength % 4) % 4;
    final int layerInfoEnd = sectionStart + 8 + layerInfoLength;
    final Uint8List padded = Uint8List.fromList([...source.sublist(0, layerInfoEnd), ...List<int>.filled(padding, 0), ...source.sublist(layerInfoEnd)]);
    ByteData.sublistView(padded)
      ..setUint32(sectionStart, view.getUint32(sectionStart) + padding)
      ..setUint32(sectionStart + 4, layerInfoLength + padding);

    expect(PsdCodec.encode(decode(padded)), padded);
  });

  test('samples changed in place are compressed again', () {
    final PsdDocument decoded = decode(PsdCodec.encode(document(layer('Layer 1'))));
    decoded.layers.single.channels.last.data[0] = 7;

    final PsdDocument reread = decode(PsdCodec.encode(decoded));

    expect(reread.layers.single.channels.last.data, [7]);
  });
  for (final PsdCompression compression in [PsdCompression.rle, PsdCompression.zipPrediction]) {
    test('retained ${compression.name} streams follow new geometry and depth', () {
      // Arrange: both a layer channel and the merged stream have 16 samples.
      final Uint8List samples = Uint8List.fromList(List.generate(16, (index) => index * 13));
      final PsdDocument original = PsdDocument(
        width: 8,
        height: 2,
        channels: 1,
        depth: 8,
        colorMode: PsdColorMode.grayscale,
        layers: [
          PsdLayer(
            rectangle: const PsdRectangle.fromSize(width: 8, height: 2),
            name: 'Pixels',
            channels: [PsdChannel(id: 0, data: samples)],
          ),
        ],
        mergedImage: [samples],
      );
      final PsdDocument source = decode(PsdCodec.encode(original, options: PsdWriteOptions(compression: compression)));
      for (final (int width, int height, int depth) in [(4, 4, 8), (4, 2, 16)]) {
        final PsdDocument reshaped = PsdDocument(
          width: width,
          height: height,
          channels: 1,
          depth: depth,
          colorMode: source.colorMode,
          layers: [
            PsdLayer(
              rectangle: PsdRectangle.fromSize(width: width, height: height),
              name: 'Pixels',
              channels: source.layers.single.channels,
            ),
          ],
          mergedImage: source.mergedImage,
          mergedImageCompression: compression,
        );
        // Act: buffers are identical, but the encoded row layout must change.
        final PsdDocument reread = decode(PsdCodec.encode(reshaped));
        // Assert.
        expect(reread.mergedImage.single, samples);
        expect(reread.layers.single.channels.single.data, samples);
      }
    });
  }

  test('retained streams do not bypass sample length validation', () {
    final PsdDocument source = decode(PsdCodec.encode(document(layer('Pixels'))));
    final PsdDocument invalid = PsdDocument(
      width: 2,
      height: 1,
      channels: 3,
      depth: 8,
      colorMode: source.colorMode,
      mergedImage: source.mergedImage,
      mergedImageCompression: source.mergedImageCompression,
    );
    expect(() => PsdCodec.encode(invalid), throwsA(isA<PsWriteException>()));
  });
}
