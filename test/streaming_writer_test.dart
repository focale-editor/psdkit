import 'dart:typed_data';

import 'package:psdkit/psdkit.dart';
import 'package:test/test.dart';

/// Verifies byte parity and bounded reads of progressive PSD output.
void main() {
  for (final PsdVersion version in PsdVersion.values) {
    test('progressive RLE output matches ${version.name} byte encoding', () async {
      final PsdDocument document = _fixture(version: version);
      final Uint8List expected = PsdCodec.encode(document);
      final _MemoryRandomAccessOutput output = _MemoryRandomAccessOutput();

      final int length = await PsdCodec.encodeTo(
        PsdStreamDocument.fromDocument(document),
        output,
        rowBatchSize: 1,
      );

      expect(length, expected.lengthInBytes);
      expect(output.bytes, orderedEquals(expected));
      final PsdDocument decoded = PsdCodec.decode(output.bytes);
      expect(decoded.version, version);
      expect(decoded.layers.single.name, 'Pixels');
      expect(decoded.layers.single.channel(-1)?.data, [255, 128, 64, 32]);
    });
  }

  test('progressive sources never receive an oversized row request', () async {
    final PsdDocument document = _fixture(version: PsdVersion.psb);
    final _TrackingPlanarSource source = _TrackingPlanarSource(
      bytes: Uint8List.fromList([
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
      ]),
      rowBytes: 2,
    );
    final PsdStreamDocument streamed = PsdStreamDocument(
      metadata: PsdDocument(
        version: PsdVersion.psb,
        width: 2,
        height: 4,
        channels: 1,
        depth: 8,
        colorMode: PsdColorMode.grayscale,
        mergedImage: const [],
      ),
      layers: const [],
      mergedImage: [source],
    );
    final _MemoryRandomAccessOutput output = _MemoryRandomAccessOutput();

    await PsdCodec.encodeTo(streamed, output, rowBatchSize: 2);

    expect(source.maximumRowsRead, 2);
    expect(source.readCount, 2);
    expect(PsdCodec.decode(output.bytes).mergedImage.single, source.bytes);
    expect(document.width, 2);
  });

  test('progressive RAW output matches byte-oriented encoding', () async {
    final PsdDocument document = _fixture(
      version: PsdVersion.psb,
      compression: PsdCompression.raw,
    );
    final Uint8List expected = PsdCodec.encode(document);
    final _MemoryRandomAccessOutput output = _MemoryRandomAccessOutput();

    await PsdCodec.encodeTo(
      PsdStreamDocument.fromDocument(document),
      output,
      rowBatchSize: 1,
    );

    expect(output.bytes, orderedEquals(expected));
  });

  test('progressive 16-bit layers use the alternate layer-info block', () async {
    final PsdDocument document = _sixteenBitFixture();
    final Uint8List expected = PsdCodec.encode(document);
    final _MemoryRandomAccessOutput output = _MemoryRandomAccessOutput();

    await PsdCodec.encodeTo(
      PsdStreamDocument.fromDocument(document),
      output,
      rowBatchSize: 1,
    );

    expect(output.bytes, orderedEquals(expected));
    final PsdDocument decoded = PsdCodec.decode(output.bytes);
    expect(decoded.depth, 16);
    expect(decoded.layers.single.channel(0)?.data, document.layers.single.channel(0)?.data);
  });

  test('RLE length backpatching crosses its bounded batch boundary', () async {
    const int height = 4101;
    final Uint8List plane = Uint8List.fromList([
      for (int row = 0; row < height; row++) row % 251,
    ]);
    final PsdDocument document = PsdDocument(
      version: PsdVersion.psb,
      width: 1,
      height: height,
      channels: 1,
      depth: 8,
      colorMode: PsdColorMode.grayscale,
      mergedImage: [plane],
      mergedImageCompression: PsdCompression.rle,
    );
    final Uint8List expected = PsdCodec.encode(document);
    final _MemoryRandomAccessOutput output = _MemoryRandomAccessOutput();

    await PsdCodec.encodeTo(
      PsdStreamDocument.fromDocument(document),
      output,
      rowBatchSize: 37,
    );

    expect(output.bytes, orderedEquals(expected));
  });

  test('progressive writer rejects ZIP instead of buffering a plane', () async {
    final PsdDocument document = _fixture(
      version: PsdVersion.psb,
      compression: PsdCompression.zip,
    );

    await expectLater(
      PsdCodec.encodeTo(
        PsdStreamDocument.fromDocument(document),
        _MemoryRandomAccessOutput(),
      ),
      throwsA(isA<PsWriteException>()),
    );
  });
}

/// Builds one high-depth fixture whose layers live in the alternate block.
PsdDocument _sixteenBitFixture() {
  final List<Uint8List> merged = [
    Uint8List.fromList([0, 1, 0x12, 0x34, 0x7F, 0xFF, 0xFF, 0xFF]),
    Uint8List.fromList([0xFF, 0xFF, 0x80, 0, 0x40, 0, 0, 0]),
    Uint8List.fromList([0, 0, 0x20, 0, 0x80, 0, 0xFF, 0xFF]),
    Uint8List.fromList([0xFF, 0xFF, 0xC0, 0, 0x80, 0, 0x40, 0]),
  ];
  return PsdDocument(
    version: PsdVersion.psb,
    width: 2,
    height: 2,
    channels: 4,
    depth: 16,
    colorMode: PsdColorMode.rgb,
    layers: [
      PsdLayer(
        rectangle: const PsdRectangle.fromSize(width: 2, height: 2),
        name: 'Sixteen bit',
        channels: [
          for (int channel = 0; channel < 3; channel++)
            PsdChannel(
              id: channel,
              data: merged[channel],
            ),
          PsdChannel(id: -1, data: merged[3]),
        ],
      ),
    ],
    mergedImage: merged,
    mergedTransparency: true,
  );
}

/// Builds a layered document with enough rows to exercise backpatching.
PsdDocument _fixture({
  required PsdVersion version,
  PsdCompression compression = PsdCompression.rle,
}) {
  final List<Uint8List> merged = [
    Uint8List.fromList([10, 20, 30, 40]),
    Uint8List.fromList([50, 60, 70, 80]),
    Uint8List.fromList([90, 100, 110, 120]),
    Uint8List.fromList([255, 255, 255, 255]),
  ];
  return PsdDocument(
    version: version,
    width: 2,
    height: 2,
    channels: 4,
    depth: 8,
    colorMode: PsdColorMode.rgb,
    layers: [
      PsdLayer(
        rectangle: const PsdRectangle.fromSize(width: 2, height: 2),
        name: 'Pixels',
        channels: [
          PsdChannel(id: 0, data: merged[0], compression: compression),
          PsdChannel(id: 1, data: merged[1], compression: compression),
          PsdChannel(id: 2, data: merged[2], compression: compression),
          PsdChannel(id: -1, data: Uint8List.fromList([255, 128, 64, 32]), compression: compression),
        ],
      ),
    ],
    mergedImage: merged,
    mergedImageCompression: compression,
    mergedTransparency: true,
  );
}

/// Records the largest row batch requested by the writer.
final class _TrackingPlanarSource implements PsdPlanarSource {
  /// Complete source bytes.
  final Uint8List bytes;

  /// Number of bytes in one row.
  final int rowBytes;

  /// Largest row count observed in one call.
  int maximumRowsRead = 0;

  /// Number of source reads performed.
  int readCount = 0;

  /// Creates a tracking source over [bytes].
  _TrackingPlanarSource({required this.bytes, required this.rowBytes});

  @override
  Future<Uint8List> readRows({required int startRow, required int rowCount}) async {
    maximumRowsRead = maximumRowsRead < rowCount ? rowCount : maximumRowsRead;
    readCount++;
    return Uint8List.sublistView(
      bytes,
      startRow * rowBytes,
      (startRow + rowCount) * rowBytes,
    );
  }
}

/// Stores random-access output in a growable test buffer.
final class _MemoryRandomAccessOutput implements PsdRandomAccessOutput {
  /// Mutable backing bytes.
  Uint8List _bytes = Uint8List(0);

  /// Current cursor.
  int _position = 0;

  /// Immutable view of the written bytes.
  Uint8List get bytes => _bytes.asUnmodifiableView();

  @override
  int get position => _position;

  @override
  Future<void> flush() async {}

  @override
  Future<void> setPosition(int position) async {
    if (position < 0 || position > _bytes.lengthInBytes) {
      throw RangeError.range(position, 0, _bytes.lengthInBytes);
    }
    _position = position;
  }

  @override
  Future<void> truncate(int length) async {
    if (length < 0) {
      throw RangeError.value(length);
    }
    final Uint8List resized = Uint8List(length);
    resized.setRange(0, length.clamp(0, _bytes.lengthInBytes), _bytes);
    _bytes = resized;
    _position = _position.clamp(0, length);
  }

  @override
  Future<void> write(Uint8List bytes) async {
    final int end = _position + bytes.lengthInBytes;
    if (end > _bytes.lengthInBytes) {
      final Uint8List grown = Uint8List(end);
      grown.setRange(0, _bytes.lengthInBytes, _bytes);
      _bytes = grown;
    }
    _bytes.setRange(_position, end, bytes);
    _position = end;
  }
}
