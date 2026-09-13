import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:psdkit/src/model.dart';
import 'package:psdkit/src/zlib.dart';

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
    throw PsFormatException(message: 'Decoded channel size $expected exceeds the configured limit');
  }
  final Uint8List decoded = switch (compression) {
    PsdCompression.raw => payload,
    PsdCompression.rle => _decodeRle(payload, rowBytes, height, wideRowLengths),
    PsdCompression.zip => _decodeZip(payload, expected),
    PsdCompression.zipPrediction => _undoPrediction(_decodeZip(payload, expected), width, height, depth),
  };
  if (decoded.length != expected) {
    throw PsFormatException(message: 'Decoded channel has ${decoded.length} bytes; expected $expected');
  }
  // A RAW payload is a view into the source file and must be detached so the
  // whole file cannot be pinned by one channel; the other codecs already
  // returned a private buffer.
  return compression == PsdCompression.raw ? Uint8List.fromList(decoded) : decoded;
}

/// Inflates [input] with an exact allocation bound and normalizes failures.
Uint8List _decodeZip(Uint8List input, int expectedBytes) {
  try {
    return psdZlibDecode(input, maxOutputBytes: expectedBytes);
  } on UnsupportedError {
    rethrow;
  } on Object catch (error) {
    throw PsFormatException(message: 'Invalid ZIP channel data: $error');
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
    throw PsWriteException(message: 'Channel has ${data.length} bytes; $width x $height at $depth-bit requires $expected');
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
    throw PsFormatException(message: 'Decoded merged image size $totalSize exceeds the configured limit');
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
      decoded = _decodeZip(payload, totalSize);
      if (decoded.length != totalSize) {
        throw PsFormatException(message: 'Decoded merged image has ${decoded.length} bytes; expected $totalSize');
      }
      for (int channel = 0; channel < channels; channel++) {
        _undoPrediction(Uint8List.sublistView(decoded, channel * channelSize, (channel + 1) * channelSize), width, height, depth);
      }
  }
  if (decoded.length != totalSize) {
    throw PsFormatException(message: 'Decoded merged image has ${decoded.length} bytes; expected $totalSize');
  }
  // Decoded buffers are private, so a single channel can keep a buffer that
  // it fills exactly. Otherwise channels are copied apart so that none pins
  // the others or unused capacity.
  if (channels == 1 && compression != PsdCompression.raw && decoded.buffer.lengthInBytes == totalSize) {
    return <Uint8List>[decoded];
  }
  return <Uint8List>[
    for (int channel = 0; channel < channels; channel++) decoded.sublist(channel * channelSize, (channel + 1) * channelSize),
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
      throw PsWriteException(message: 'Merged channel has ${channel.length} bytes; expected $channelSize');
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
Uint8List _decodeRle(Uint8List input, int rowBytes, int height, bool wide) => PsPackBitsCodec.decodeRows(
  input,
  rowBytes: rowBytes,
  rowCount: height,
  wideRowLengths: wide,
);

/// Encodes [height] rows and prefixes their 16-bit or 32-bit lengths.
Uint8List _encodeRle(Uint8List input, int rowBytes, int height, bool wide) => PsPackBitsCodec.encodeRows(
  input,
  rowBytes: rowBytes,
  rowCount: height,
  wideRowLengths: wide,
);

/// Reverses horizontal sample differencing in place and returns [samples].
///
/// [samples] must be a private buffer, such as freshly inflated data. A buffer
/// of the wrong length is returned unchanged for the caller to reject.
Uint8List _undoPrediction(Uint8List samples, int width, int height, int depth) {
  if (depth == 1) {
    throw const PsFormatException(message: 'ZIP prediction is not valid for 1-bit data');
  }
  final int rowBytes = width * (depth ~/ 8);
  if (samples.length != rowBytes * height || rowBytes == 0) {
    return samples;
  }
  switch (depth) {
    case 8:
      for (int rowStart = 0; rowStart < samples.length; rowStart += rowBytes) {
        int previous = samples[rowStart];
        for (int offset = rowStart + 1; offset < rowStart + rowBytes; offset++) {
          previous = (previous + samples[offset]) & 0xff;
          samples[offset] = previous;
        }
      }
    case 16:
      // Samples are big-endian; each running sum is written back byte by byte.
      for (int rowStart = 0; rowStart < samples.length; rowStart += rowBytes) {
        int previous = (samples[rowStart] << 8) | samples[rowStart + 1];
        for (int offset = rowStart + 2; offset < rowStart + rowBytes; offset += 2) {
          previous = (previous + ((samples[offset] << 8) | samples[offset + 1])) & 0xffff;
          samples[offset] = previous >>> 8;
          samples[offset + 1] = previous & 0xff;
        }
      }
    case 32:
      _undoFloatPrediction(samples, width);
  }
  return samples;
}

/// Applies horizontal sample differencing before ZIP compression.
Uint8List _applyPrediction(Uint8List input, int width, int height, int depth) {
  if (depth == 1) {
    throw const PsWriteException(message: 'ZIP prediction is not valid for 1-bit data');
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

/// Reverses Photoshop's byte predictor and byte-plane shuffle in place.
///
/// Each row stores the first byte of every pixel, then every second byte, and
/// so on, with each byte predicted from the one before it. Only one row of
/// working storage is allocated.
void _undoFloatPrediction(Uint8List samples, int width) {
  final int rowBytes = width * 4;
  final Uint8List planes = Uint8List(rowBytes);
  for (int rowStart = 0; rowStart < samples.length; rowStart += rowBytes) {
    int previous = samples[rowStart];
    planes[0] = previous;
    for (int index = 1; index < rowBytes; index++) {
      previous = (previous + samples[rowStart + index]) & 0xff;
      planes[index] = previous;
    }
    for (int byte = 0; byte < 4; byte++) {
      final int planeStart = byte * width;
      for (int pixel = 0; pixel < width; pixel++) {
        samples[rowStart + pixel * 4 + byte] = planes[planeStart + pixel];
      }
    }
  }
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
