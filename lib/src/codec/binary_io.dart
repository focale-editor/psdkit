part of '../codec.dart';

/// Largest canvas allowed by PSB, exactly representable on every platform.
const int _maximumWritablePixels = 300000 * 300000;

/// Reads four signed PSD edges from [reader].
PsdRectangle _readRectangle(PsBinaryReader reader) => PsdRectangle(top: reader.readInt32(), left: reader.readInt32(), bottom: reader.readInt32(), right: reader.readInt32());

/// Writes the four signed edges of [rectangle].
void _writeRectangle(PsBinaryWriter writer, PsdRectangle rectangle) {
  writer
    ..writeInt32(rectangle.top)
    ..writeInt32(rectangle.left)
    ..writeInt32(rectangle.bottom)
    ..writeInt32(rectangle.right);
}

/// Resolves the sample bounds belonging to [channelId] on [layer].
PsdRectangle _channelRectangle(PsdLayer layer, int channelId) {
  if (channelId == -2 && layer.mask != null) {
    return layer.mask!.rectangle;
  }
  if (channelId == -3 && layer.mask?.realRectangle != null) {
    return layer.mask!.realRectangle!;
  }
  return layer.rectangle;
}

/// Replaces placeholder channels while retaining every metadata field.
PsdLayer _copyLayer(PsdLayer layer, List<PsdChannel> channels) => PsdLayer(
  rectangle: layer.rectangle,
  name: layer.name,
  channels: channels,
  blendMode: layer.blendMode,
  opacity: layer.opacity,
  clipping: layer.clipping,
  flags: layer.flags,
  mask: layer.mask,
  blendingRanges: layer.blendingRanges,
  additionalInfo: layer.additionalInfo,
  writesUnicodeName: layer.writesUnicodeName,
);

/// Resolves a supported PSD enum value or reports its byte location.
T _enumByCode<T>(List<T> values, int code, String label, PsBinaryReader reader) {
  for (final T value in values) {
    final int valueCode = switch (value) {
      PsdVersion(code: final int itemCode) => itemCode,
      PsdColorMode(code: final int itemCode) => itemCode,
      PsdCompression(code: final int itemCode) => itemCode,
      _ => -1,
    };
    if (valueCode == code) {
      return value;
    }
  }
  throw PsFormatException(message: 'Unsupported $label $code', source: reader.bytes, offset: reader.baseOffset + reader.offset);
}

/// Validates header ranges before allocations or serialization.
void _validateHeader({
  required PsdVersion version,
  required int channels,
  required int width,
  required int height,
  required int depth,
  required int maxPixels,
  required bool writing,
}) {
  final void Function(String message) fail = writing ? (message) => throw PsWriteException(message: message) : (message) => throw PsFormatException(message: message);
  if (channels < 1 || channels > 56) {
    fail('Channel count must be between 1 and 56');
  }
  final int dimensionLimit = version == PsdVersion.psd ? 30000 : 300000;
  if (width < 1 || height < 1 || width > dimensionLimit || height > dimensionLimit) {
    fail('${version.name.toUpperCase()} dimensions must be between 1 and $dimensionLimit pixels');
  }
  if (width * height > maxPixels) {
    fail('Canvas area ${width * height} exceeds the configured limit $maxPixels');
  }
  if (depth != 1 && depth != 8 && depth != 16 && depth != 32) {
    fail('Depth must be 1, 8, 16, or 32 bits');
  }
}

/// Ensures that [value] fits a four-byte Photoshop signature field.
void _requireFourCharacters(String value, String label) {
  if (value.length != 4 || value.codeUnits.any((unit) => unit > 0xff)) {
    throw PsWriteException(message: '$label must contain exactly four one-byte characters');
  }
}
