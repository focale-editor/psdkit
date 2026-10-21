part of '../codec.dart';

/// Encodes planar samples in bounded batches independently of PSD sections.
final class _PsdPlaneWriter {
  /// Destination receiving encoded rows and their length tables.
  final PsdRandomAccessOutput output;

  /// Maximum rows requested from a source at once.
  final int rowBatchSize;

  /// Reports source rows after their encoded bytes have been written.
  final void Function(int count) onRows;

  /// Creates a pixel writer sharing its caller's destination and progress.
  const _PsdPlaneWriter({
    required this.output,
    required this.rowBatchSize,
    required this.onRows,
  });

  /// Writes one or more planes using bounded source reads.
  Future<void> write(
    List<PsdPlanarSource> sources, {
    required PsdCompression compression,
    required int width,
    required int height,
    required int depth,
    required bool wideRowLengths,
  }) async {
    switch (compression) {
      case PsdCompression.raw:
        for (final PsdPlanarSource source in sources) {
          await _writeRawPlane(
            source,
            width: width,
            height: height,
            depth: depth,
          );
        }
      case PsdCompression.rle:
        await _writeRlePlanes(
          sources,
          width: width,
          height: height,
          depth: depth,
          wideRowLengths: wideRowLengths,
        );
      case PsdCompression.zip || PsdCompression.zipPrediction:
        throw const PsWriteException(
          message:
              'Progressive PSD writing supports RAW and RLE compression; '
              'use PsdCodec.encode for ZIP compression',
        );
    }
  }

  /// Copies a raw plane in bounded row batches.
  Future<void> _writeRawPlane(
    PsdPlanarSource source, {
    required int width,
    required int height,
    required int depth,
  }) async {
    final int rowBytes = psdRowBytes(width, depth);
    for (int startRow = 0; startRow < height;) {
      final int count = (height - startRow).clamp(1, rowBatchSize);
      final Uint8List rows = await source.readRows(
        startRow: startRow,
        rowCount: count,
      );
      _validateRows(rows, rowBytes: rowBytes, rowCount: count);
      await output.write(rows);
      startRow += count;
      onRows(count);
    }
  }

  /// Writes PackBits row bodies while backpatching bounded length batches.
  Future<void> _writeRlePlanes(
    List<PsdPlanarSource> sources, {
    required int width,
    required int height,
    required int depth,
    required bool wideRowLengths,
  }) async {
    final int rowBytes = psdRowBytes(width, depth);
    final int lengthBytes = wideRowLengths ? 4 : 2;
    final int rowCount = height * sources.length;
    final int tableOffset = output.position;
    await _writeZeros(rowCount * lengthBytes);
    const int lengthsPerBatch = 4096;
    final Uint32List lengths = Uint32List(lengthsPerBatch);
    int batchStartIndex = 0;
    int lengthIndex = 0;
    for (final PsdPlanarSource source in sources) {
      for (int startRow = 0; startRow < height;) {
        final int count = (height - startRow).clamp(1, rowBatchSize);
        final Uint8List rows = await source.readRows(
          startRow: startRow,
          rowCount: count,
        );
        _validateRows(rows, rowBytes: rowBytes, rowCount: count);
        for (int row = 0; row < count; row++) {
          final Uint8List encoded = PsPackBitsCodec.encodeRow(
            Uint8List.sublistView(
              rows,
              row * rowBytes,
              (row + 1) * rowBytes,
            ),
          );
          if (!wideRowLengths && encoded.lengthInBytes > 0xffff) {
            throw const PsWriteException(
              message:
                  'A PSD PackBits row exceeds 65535 encoded bytes; '
                  'use PSB or ZIP',
            );
          }
          lengths[lengthIndex - batchStartIndex] = encoded.lengthInBytes;
          lengthIndex++;
          await output.write(encoded);
          if (lengthIndex - batchStartIndex == lengths.length) {
            await _patchRleRowLengths(
              tableOffset,
              batchStartIndex,
              lengths,
              lengths.length,
              lengthBytes,
            );
            batchStartIndex = lengthIndex;
          }
        }
        startRow += count;
        onRows(count);
      }
    }
    final int remaining = lengthIndex - batchStartIndex;
    if (remaining > 0) {
      await _patchRleRowLengths(
        tableOffset,
        batchStartIndex,
        lengths,
        remaining,
        lengthBytes,
      );
    }
  }

  /// Backpatches [count] row lengths without losing the append position.
  Future<void> _patchRleRowLengths(
    int tableOffset,
    int startIndex,
    Uint32List lengths,
    int count,
    int lengthBytes,
  ) async {
    final int end = output.position;
    await output.setPosition(tableOffset + startIndex * lengthBytes);
    final Uint8List bytes = Uint8List(count * lengthBytes);
    final ByteData values = ByteData.sublistView(bytes);
    for (int index = 0; index < count; index++) {
      final int value = lengths[index];
      if (lengthBytes == 4) {
        values.setUint32(index * 4, value);
      } else {
        values.setUint16(index * 2, value);
      }
    }
    await output.write(bytes);
    await output.setPosition(end);
  }

  /// Verifies that one source fulfilled its exact row contract.
  void _validateRows(
    Uint8List rows, {
    required int rowBytes,
    required int rowCount,
  }) {
    final int expected = rowBytes * rowCount;
    if (rows.lengthInBytes != expected) {
      throw PsWriteException(
        message:
            'Planar source returned ${rows.lengthInBytes} bytes; '
            '$rowCount rows require $expected',
      );
    }
  }

  /// Writes [count] zero bytes without allocating one giant placeholder.
  Future<void> _writeZeros(int count) async {
    const int batchSize = 64 * 1024;
    final Uint8List batch = Uint8List(batchSize);
    int remaining = count;
    while (remaining > 0) {
      final int written = remaining.clamp(1, batchSize);
      await output.write(
        written == batchSize ? batch : Uint8List.sublistView(batch, 0, written),
      );
      remaining -= written;
    }
  }
}
