import 'dart:typed_data';

import 'package:psdkit/src/exceptions.dart';
import 'package:psdkit/src/model.dart';
import 'package:psdkit/src/zlib_backend.dart';

/// Returns the number of stored bytes in one planar row.
int psdRowBytes(int width, int depth) => (width * depth + 7) ~/ 8;

/// Decodes one channel payload after its compression marker.
Uint8List decodePsdChannel({
  required PsdCompression compression,
  required Uint8List payload,
  required int width,
  required int height,
  required int depth,
  required bool wideRowLengths,
  required int maxDecodedBytes,
}) {
  final int rowBytes = psdRowBytes(width, depth);
  final int expected = rowBytes * height;
  if (expected > maxDecodedBytes) {
    throw PsdFormatException('Decoded channel size $expected exceeds the configured limit');
  }
  final Uint8List decoded = switch (compression) {
    PsdCompression.raw => payload,
    PsdCompression.rle => _decodeRle(payload, rowBytes, height, wideRowLengths),
    PsdCompression.zip => _decodeZip(payload, expected),
    PsdCompression.zipPrediction => _undoPrediction(
      _decodeZip(payload, expected),
      width,
      height,
      depth,
    ),
  };
  if (decoded.length != expected) {
    throw PsdFormatException('Decoded channel has ${decoded.length} bytes; expected $expected');
  }
  return Uint8List.fromList(decoded);
}

/// Inflates [input] with an exact allocation bound and normalizes failures.
Uint8List _decodeZip(Uint8List input, int expectedBytes) {
  try {
    return psdZlibDecode(input, maxOutputBytes: expectedBytes);
  } on UnsupportedError {
    rethrow;
  } on Object catch (error) {
    throw PsdFormatException('Invalid ZIP channel data: $error');
  }
}

/// Encodes uncompressed samples without their two-byte compression marker.
Uint8List encodePsdChannel({
  required PsdCompression compression,
  required Uint8List data,
  required int width,
  required int height,
  required int depth,
  required bool wideRowLengths,
}) {
  final int expected = psdRowBytes(width, depth) * height;
  if (data.length != expected) {
    throw PsdWriteException('Channel has ${data.length} bytes; $width x $height at $depth-bit requires $expected');
  }
  return switch (compression) {
    PsdCompression.raw => data,
    PsdCompression.rle => _encodeRle(data, psdRowBytes(width, depth), height, wideRowLengths),
    PsdCompression.zip => psdZlibEncode(data),
    PsdCompression.zipPrediction => psdZlibEncode(_applyPrediction(data, width, height, depth)),
  };
}

/// Decodes the single compression stream used by all merged-image channels.
List<Uint8List> decodePsdMergedImage({
  required PsdCompression compression,
  required Uint8List payload,
  required int channels,
  required int width,
  required int height,
  required int depth,
  required bool wideRowLengths,
  required int maxDecodedBytes,
}) {
  final int channelSize = psdRowBytes(width, depth) * height;
  final int totalSize = channelSize * channels;
  if (totalSize > maxDecodedBytes) {
    throw PsdFormatException('Decoded merged image size $totalSize exceeds the configured limit');
  }
  late final Uint8List decoded;
  switch (compression) {
    case PsdCompression.raw:
      decoded = payload;
    case PsdCompression.rle:
      decoded = _decodeRle(payload, psdRowBytes(width, depth), height * channels, wideRowLengths);
    case PsdCompression.zip:
      decoded = _decodeZip(payload, totalSize);
    case PsdCompression.zipPrediction:
      final Uint8List predicted = _decodeZip(payload, totalSize);
      if (predicted.length != totalSize) {
        throw PsdFormatException('Decoded merged image has ${predicted.length} bytes; expected $totalSize');
      }
      final BytesBuilder result = BytesBuilder(copy: false);
      for (int channel = 0; channel < channels; channel++) {
        result.add(_undoPrediction(Uint8List.sublistView(predicted, channel * channelSize, (channel + 1) * channelSize), width, height, depth));
      }
      decoded = result.takeBytes();
  }
  if (decoded.length != totalSize) {
    throw PsdFormatException('Decoded merged image has ${decoded.length} bytes; expected $totalSize');
  }
  return <Uint8List>[
    for (int channel = 0; channel < channels; channel++) Uint8List.fromList(Uint8List.sublistView(decoded, channel * channelSize, (channel + 1) * channelSize)),
  ];
}

/// Encodes merged-image channels into their shared compression stream.
Uint8List encodePsdMergedImage({
  required PsdCompression compression,
  required List<Uint8List> channels,
  required int width,
  required int height,
  required int depth,
  required bool wideRowLengths,
}) {
  final int channelSize = psdRowBytes(width, depth) * height;
  for (final Uint8List channel in channels) {
    if (channel.length != channelSize) {
      throw PsdWriteException('Merged channel has ${channel.length} bytes; expected $channelSize');
    }
  }
  final BytesBuilder joined = BytesBuilder(copy: false);
  if (compression == PsdCompression.zipPrediction) {
    for (final Uint8List channel in channels) {
      joined.add(_applyPrediction(channel, width, height, depth));
    }
  } else {
    channels.forEach(joined.add);
  }
  final Uint8List data = joined.takeBytes();
  return switch (compression) {
    PsdCompression.raw => data,
    PsdCompression.rle => _encodeRle(data, psdRowBytes(width, depth), height * channels.length, wideRowLengths),
    PsdCompression.zip || PsdCompression.zipPrediction => psdZlibEncode(data),
  };
}

/// Decodes [height] PackBits rows after their shared length table.
Uint8List _decodeRle(Uint8List input, int rowBytes, int height, bool wide) {
  final int tableSize = height * (wide ? 4 : 2);
  if (input.length < tableSize) {
    throw const PsdFormatException('Truncated RLE row-length table');
  }
  final ByteData lengths = ByteData.sublistView(input, 0, tableSize);
  final Uint8List output = Uint8List(rowBytes * height);
  int inputOffset = tableSize;
  for (int row = 0; row < height; row++) {
    final int encodedLength = wide ? lengths.getUint32(row * 4) : lengths.getUint16(row * 2);
    final int end = inputOffset + encodedLength;
    if (end > input.length) {
      throw const PsdFormatException('Truncated PackBits row');
    }
    int outputOffset = row * rowBytes;
    final int outputEnd = outputOffset + rowBytes;
    while (inputOffset < end && outputOffset < outputEnd) {
      final int header = input[inputOffset++];
      if (header <= 127) {
        final int count = header + 1;
        if (inputOffset + count > end || outputOffset + count > outputEnd) {
          throw const PsdFormatException('Invalid PackBits literal run');
        }
        output.setRange(outputOffset, outputOffset + count, input, inputOffset);
        inputOffset += count;
        outputOffset += count;
      } else if (header >= 129) {
        final int count = 257 - header;
        if (inputOffset >= end || outputOffset + count > outputEnd) {
          throw const PsdFormatException('Invalid PackBits repeated run');
        }
        output.fillRange(outputOffset, outputOffset + count, input[inputOffset++]);
        outputOffset += count;
      }
    }
    if (outputOffset != outputEnd || inputOffset != end) {
      throw const PsdFormatException('PackBits row does not match its declared width');
    }
  }
  if (inputOffset != input.length) {
    throw const PsdFormatException('Unexpected bytes after PackBits rows');
  }
  return output;
}

/// Encodes [height] rows and prefixes their 16-bit or 32-bit lengths.
Uint8List _encodeRle(Uint8List input, int rowBytes, int height, bool wide) {
  final List<Uint8List> rows = <Uint8List>[];
  for (int row = 0; row < height; row++) {
    rows.add(_encodePackBits(Uint8List.sublistView(input, row * rowBytes, (row + 1) * rowBytes)));
  }
  final int lengthSize = wide ? 4 : 2;
  final int payloadLength = rows.fold<int>(height * lengthSize, (total, row) => total + row.length);
  final Uint8List result = Uint8List(payloadLength);
  final ByteData table = ByteData.sublistView(result);
  int offset = height * lengthSize;
  for (int row = 0; row < height; row++) {
    final int length = rows[row].length;
    if (!wide && length > 0xffff) {
      throw const PsdWriteException('A PSD PackBits row exceeds 65535 encoded bytes; use PSB or ZIP');
    }
    if (wide) {
      table.setUint32(row * 4, length);
    } else {
      table.setUint16(row * 2, length);
    }
    result.setRange(offset, offset + length, rows[row]);
    offset += length;
  }
  return result;
}

/// Encodes one [row] with the PackBits run-length algorithm.
Uint8List _encodePackBits(Uint8List row) {
  final BytesBuilder output = BytesBuilder(copy: false);
  int offset = 0;
  while (offset < row.length) {
    int run = 1;
    while (offset + run < row.length && run < 128 && row[offset + run] == row[offset]) {
      run++;
    }
    if (run >= 3) {
      output.add(<int>[257 - run, row[offset]]);
      offset += run;
      continue;
    }
    final int literalStart = offset;
    offset += run;
    while (offset < row.length && offset - literalStart < 128) {
      run = 1;
      while (offset + run < row.length && run < 128 && row[offset + run] == row[offset]) {
        run++;
      }
      if (run >= 3) {
        break;
      }
      final int remaining = 128 - (offset - literalStart);
      offset += run.clamp(1, remaining);
    }
    final int count = offset - literalStart;
    output.add(<int>[count - 1]);
    output.add(Uint8List.sublistView(row, literalStart, offset));
  }
  return output.takeBytes();
}

/// Reverses horizontal sample differencing on decompressed bytes.
Uint8List _undoPrediction(Uint8List input, int width, int height, int depth) {
  if (depth == 1) {
    throw const PsdFormatException('ZIP prediction is not valid for 1-bit data');
  }
  final Uint8List output = Uint8List.fromList(input);
  final int bytesPerSample = depth ~/ 8;
  final int rowBytes = width * bytesPerSample;
  if (output.length != rowBytes * height) {
    return output;
  }
  if (depth == 32) {
    return _undoFloatPrediction(output, width, height);
  }
  final ByteData values = ByteData.sublistView(output);
  for (int row = 0; row < height; row++) {
    final int start = row * rowBytes;
    for (int column = 1; column < width; column++) {
      final int offset = start + column * bytesPerSample;
      final int previous = offset - bytesPerSample;
      switch (depth) {
        case 8:
          output[offset] = (output[offset] + output[previous]) & 0xff;
        case 16:
          values.setUint16(offset, (values.getUint16(offset) + values.getUint16(previous)) & 0xffff);
      }
    }
  }
  return output;
}

/// Applies horizontal sample differencing before ZIP compression.
Uint8List _applyPrediction(Uint8List input, int width, int height, int depth) {
  if (depth == 1) {
    throw const PsdWriteException('ZIP prediction is not valid for 1-bit data');
  }
  if (depth == 32) {
    return _applyFloatPrediction(input, width, height);
  }
  final Uint8List output = Uint8List.fromList(input);
  final int bytesPerSample = depth ~/ 8;
  final int rowBytes = width * bytesPerSample;
  final ByteData source = ByteData.sublistView(input);
  final ByteData values = ByteData.sublistView(output);
  for (int row = 0; row < height; row++) {
    final int start = row * rowBytes;
    for (int column = width - 1; column > 0; column--) {
      final int offset = start + column * bytesPerSample;
      final int previous = offset - bytesPerSample;
      switch (depth) {
        case 8:
          output[offset] = (input[offset] - input[previous]) & 0xff;
        case 16:
          values.setUint16(offset, (source.getUint16(offset) - source.getUint16(previous)) & 0xffff);
      }
    }
  }
  return output;
}

/// Reverses Photoshop's byte-plane shuffle and byte predictor for 32-bit rows.
Uint8List _undoFloatPrediction(Uint8List input, int width, int height) {
  final int rowBytes = width * 4;
  final Uint8List predicted = Uint8List.fromList(input);
  final Uint8List output = Uint8List(input.length);
  for (int row = 0; row < height; row++) {
    final int rowStart = row * rowBytes;
    final int rowEnd = rowStart + rowBytes;
    for (int offset = rowStart + 1; offset < rowEnd; offset++) {
      predicted[offset] = (predicted[offset] + predicted[offset - 1]) & 0xff;
    }
    for (int pixel = 0; pixel < width; pixel++) {
      for (int byte = 0; byte < 4; byte++) {
        output[rowStart + pixel * 4 + byte] = predicted[rowStart + byte * width + pixel];
      }
    }
  }
  return output;
}

/// Applies Photoshop's byte-plane shuffle and byte predictor to 32-bit rows.
Uint8List _applyFloatPrediction(Uint8List input, int width, int height) {
  final int rowBytes = width * 4;
  final Uint8List output = Uint8List(input.length);
  for (int row = 0; row < height; row++) {
    final int rowStart = row * rowBytes;
    for (int byte = 0; byte < 4; byte++) {
      for (int pixel = 0; pixel < width; pixel++) {
        output[rowStart + byte * width + pixel] = input[rowStart + pixel * 4 + byte];
      }
    }
    for (int offset = rowStart + rowBytes - 1; offset > rowStart; offset--) {
      output[offset] = (output[offset] - output[offset - 1]) & 0xff;
    }
  }
  return output;
}
