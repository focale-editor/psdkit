import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pscore/pscore.dart';
import 'package:psdkit/src/model.dart';

/// An 8-bit, straight-alpha RGBA pixel buffer.
final class PsdRgbaImage {
  /// Pixel width.
  final int width;

  /// Pixel height.
  final int height;

  /// Interleaved red, green, blue, and alpha bytes.
  final Uint8List bytes;

  /// Creates an image from four interleaved bytes per pixel.
  const PsdRgbaImage({required this.width, required this.height, required this.bytes});
}

/// Converts decoded PSD channels into display-ready RGBA pixels.
abstract final class PsdPixels {
  /// Splits straight-alpha RGBA [image] pixels into PSD RGB channel planes.
  ///
  /// The returned fourth plane is alpha when [includeAlpha] is true.
  static List<Uint8List> encodeRgb(PsdRgbaImage image, {bool includeAlpha = true}) {
    final int pixelCount = image.width * image.height;
    if (image.bytes.length != pixelCount * 4) {
      throw PsWriteException(message: 'RGBA image has ${image.bytes.length} bytes; expected ${pixelCount * 4}');
    }
    final List<Uint8List> result = <Uint8List>[
      Uint8List(pixelCount),
      Uint8List(pixelCount),
      Uint8List(pixelCount),
      if (includeAlpha) Uint8List(pixelCount),
    ];
    for (int pixel = 0; pixel < pixelCount; pixel++) {
      final int offset = pixel * 4;
      result[0][pixel] = image.bytes[offset];
      result[1][pixel] = image.bytes[offset + 1];
      result[2][pixel] = image.bytes[offset + 2];
      if (includeAlpha) {
        result[3][pixel] = image.bytes[offset + 3];
      }
    }
    return result;
  }

  /// Converts the document's merged image.
  static PsdRgbaImage decodeMerged(PsdDocument document) => _decode(
    width: document.width,
    height: document.height,
    depth: document.depth,
    colorMode: document.colorMode,
    colorModeData: document.colorModeData,
    components: document.mergedImage,
    alphaIndex: _baseChannels(document.colorMode),
  );

  /// Converts a layer's colour and transparency channels.
  static PsdRgbaImage decodeLayer(PsdDocument document, PsdLayer layer) {
    final int baseChannels = _baseChannels(document.colorMode);
    final List<Uint8List> components = <Uint8List>[];
    for (int id = 0; id < baseChannels; id++) {
      final PsdChannel? channel = layer.channel(id);
      if (channel == null) {
        throw PsFormatException(message: 'Layer "${layer.name}" is missing color channel $id');
      }
      components.add(channel.data);
    }
    final PsdChannel? alpha = layer.channel(-1);
    if (alpha != null) {
      components.add(alpha.data);
    }
    return _decode(
      width: layer.rectangle.width,
      height: layer.rectangle.height,
      depth: document.depth,
      colorMode: document.colorMode,
      colorModeData: document.colorModeData,
      components: components,
      alphaIndex: alpha == null ? -1 : baseChannels,
    );
  }

  /// Converts planar [components] into a straight-alpha RGBA buffer.
  static PsdRgbaImage _decode({
    required int width,
    required int height,
    required int depth,
    required PsdColorMode colorMode,
    required Uint8List colorModeData,
    required List<Uint8List> components,
    required int alphaIndex,
  }) {
    final int requiredComponents = _baseChannels(colorMode);
    if (components.length < requiredComponents) {
      throw PsFormatException(message: '${colorMode.name} needs $requiredComponents color channels; found ${components.length}');
    }
    final int pixelCount = width * height;
    final Uint8List output = Uint8List(pixelCount * 4);
    // One big-endian view per plane: rebuilding them per sample dominated the
    // cost of 16-bit and 32-bit documents.
    final List<ByteData> views = <ByteData>[for (final Uint8List component in components) ByteData.sublistView(component)];
    const int red = 0;
    final int green = components.length > 1 ? 1 : 0;
    final int blue = components.length > 2 ? 2 : 0;
    final bool hasAlpha = alphaIndex >= 0 && alphaIndex < components.length;

    /// Reads one component sample using the document depth.
    int sample(int index, int pixel, {bool bitmap = false}) => _sample(components[index], views[index], pixel, width, depth, bitmap: bitmap);
    for (int pixel = 0; pixel < pixelCount; pixel++) {
      final int offset = pixel * 4;
      switch (colorMode) {
        case PsdColorMode.bitmap:
          _writeGray(output, offset, sample(0, pixel, bitmap: true));
        case PsdColorMode.grayscale || PsdColorMode.duotone:
          _writeGray(output, offset, sample(0, pixel));
        case PsdColorMode.indexed:
          _writeIndexed(output, offset, colorModeData, sample(0, pixel));
        case PsdColorMode.rgb || PsdColorMode.multichannel:
          output[offset] = sample(red, pixel);
          output[offset + 1] = sample(green, pixel);
          output[offset + 2] = sample(blue, pixel);
        case PsdColorMode.cmyk:
          _writeCmyk(output, offset, sample(0, pixel), sample(1, pixel), sample(2, pixel), sample(3, pixel));
        case PsdColorMode.lab:
          _writeLab(output, offset, sample(0, pixel), sample(1, pixel), sample(2, pixel));
      }
      output[offset + 3] = hasAlpha ? sample(alphaIndex, pixel) : 255;
    }
    return PsdRgbaImage(width: width, height: height, bytes: output);
  }
}

/// Returns the number of colour channels intrinsic to [mode].
int _baseChannels(PsdColorMode mode) => switch (mode) {
  PsdColorMode.bitmap || PsdColorMode.grayscale || PsdColorMode.indexed || PsdColorMode.duotone => 1,
  PsdColorMode.rgb || PsdColorMode.lab => 3,
  PsdColorMode.cmyk => 4,
  PsdColorMode.multichannel => 1,
};

/// Converts one sample into an unsigned 8-bit value.
///
/// [data] must be a big-endian view of [bytes]; the caller keeps one view per
/// plane so that deep documents do not allocate a view for every sample.
int _sample(Uint8List bytes, ByteData data, int pixel, int width, int depth, {bool bitmap = false}) {
  switch (depth) {
    case 1:
      final int row = pixel ~/ width;
      final int column = pixel % width;
      final int bit = bytes[row * ((width + 7) ~/ 8) + column ~/ 8] >> (7 - column % 8) & 1;
      return bitmap ? (bit == 0 ? 255 : 0) : bit * 255;
    case 8:
      return bytes[pixel];
    case 16:
      return (data.getUint16(pixel * 2) * 255 / 65535).round();
    case 32:
      final double value = data.getFloat32(pixel * 4);
      if (!value.isFinite) {
        return 0;
      }
      return (value.clamp(0.0, 1.0) * 255).round();
  }
  throw PsFormatException(message: 'Unsupported sample depth $depth');
}

/// Writes one grayscale [value] as three RGB components at [offset].
void _writeGray(Uint8List output, int offset, int value) {
  output[offset] = value;
  output[offset + 1] = value;
  output[offset + 2] = value;
}

/// Resolves an indexed-colour [index] through the planar [palette].
void _writeIndexed(Uint8List output, int offset, Uint8List palette, int index) {
  if (palette.length < 768) {
    throw const PsFormatException(message: 'Indexed color data must contain a 768-byte palette');
  }
  output[offset] = palette[index];
  output[offset + 1] = palette[256 + index];
  output[offset + 2] = palette[512 + index];
}

/// Converts four 8-bit CMYK components into sRGB at [offset].
void _writeCmyk(Uint8List output, int offset, int cyan, int magenta, int yellow, int black) {
  // PSD stores CMYK channels inverted: 255 means no ink for both each colour
  // component and black.
  final double cyanInverse = cyan / 255;
  final double magentaInverse = magenta / 255;
  final double yellowInverse = yellow / 255;
  final double blackInverse = black / 255;
  output[offset] = (255 * cyanInverse * blackInverse).round();
  output[offset + 1] = (255 * magentaInverse * blackInverse).round();
  output[offset + 2] = (255 * yellowInverse * blackInverse).round();
}

/// Converts three 8-bit CIE Lab components into sRGB at [offset].
void _writeLab(Uint8List output, int offset, int lightnessValue, int aValue, int bValue) {
  final double lightness = lightnessValue * 100 / 255;
  final double a = aValue - 128;
  final double b = bValue - 128;
  final double fy = (lightness + 16) / 116;
  final double fx = fy + a / 500;
  final double fz = fy - b / 200;
  final double x = 0.96422 * _labPivot(fx);
  final double y = _labPivot(fy);
  final double z = 0.82521 * _labPivot(fz);
  final double linearRed = 3.1338561 * x - 1.6168667 * y - 0.4906146 * z;
  final double linearGreen = -0.9787684 * x + 1.9161415 * y + 0.033454 * z;
  final double linearBlue = 0.0719453 * x - 0.2289914 * y + 1.4052427 * z;
  output[offset] = _srgb(linearRed);
  output[offset + 1] = _srgb(linearGreen);
  output[offset + 2] = _srgb(linearBlue);
}

/// Applies the inverse CIE Lab transfer curve to [value].
double _labPivot(double value) {
  const double delta = 6 / 29;
  return value > delta ? value * value * value : 3 * delta * delta * (value - 4 / 29);
}

/// Encodes a linear-light [value] as an 8-bit sRGB component.
int _srgb(double value) {
  final double encoded = value <= 0.0031308 ? 12.92 * value : 1.055 * math.pow(value, 1 / 2.4) - 0.055;
  return (encoded.clamp(0.0, 1.0) * 255).round();
}
