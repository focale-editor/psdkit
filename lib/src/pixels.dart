import 'dart:math' as math;
import 'dart:typed_data';

import 'package:psdkit/src/exceptions.dart';
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
      throw PsdWriteException('RGBA image has ${image.bytes.length} bytes; expected ${pixelCount * 4}');
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
        throw PsdFormatException('Layer "${layer.name}" is missing color channel $id');
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
      throw PsdFormatException('${colorMode.name} needs $requiredComponents color channels; found ${components.length}');
    }
    final int pixelCount = width * height;
    final Uint8List output = Uint8List(pixelCount * 4);
    int sample(Uint8List bytes, int pixel, {bool bitmap = false}) => _sample(bytes, pixel, width, depth, bitmap: bitmap);
    for (int pixel = 0; pixel < pixelCount; pixel++) {
      final List<int> color = switch (colorMode) {
        PsdColorMode.bitmap => _gray(sample(components[0], pixel, bitmap: true)),
        PsdColorMode.grayscale || PsdColorMode.duotone => _gray(sample(components[0], pixel)),
        PsdColorMode.indexed => _indexed(colorModeData, sample(components[0], pixel)),
        PsdColorMode.rgb || PsdColorMode.multichannel => <int>[
          sample(components[0], pixel),
          sample(components.length > 1 ? components[1] : components[0], pixel),
          sample(components.length > 2 ? components[2] : components[0], pixel),
        ],
        PsdColorMode.cmyk => _cmyk(<int>[for (int index = 0; index < 4; index++) sample(components[index], pixel)]),
        PsdColorMode.lab => _lab(<int>[for (int index = 0; index < 3; index++) sample(components[index], pixel)]),
      };
      final int offset = pixel * 4;
      output[offset] = color[0];
      output[offset + 1] = color[1];
      output[offset + 2] = color[2];
      output[offset + 3] = alphaIndex >= 0 && alphaIndex < components.length ? sample(components[alphaIndex], pixel) : 255;
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

/// Converts one sample from [bytes] into an unsigned 8-bit value.
int _sample(Uint8List bytes, int pixel, int width, int depth, {bool bitmap = false}) {
  switch (depth) {
    case 1:
      final int row = pixel ~/ width;
      final int column = pixel % width;
      final int bit = bytes[row * ((width + 7) ~/ 8) + column ~/ 8] >> (7 - column % 8) & 1;
      return bitmap ? (bit == 0 ? 255 : 0) : bit * 255;
    case 8:
      return bytes[pixel];
    case 16:
      return (ByteData.sublistView(bytes).getUint16(pixel * 2) * 255 / 65535).round();
    case 32:
      final double value = ByteData.sublistView(bytes).getFloat32(pixel * 4);
      if (!value.isFinite) {
        return 0;
      }
      return (value.clamp(0.0, 1.0) * 255).round();
  }
  throw PsdFormatException('Unsupported sample depth $depth');
}

/// Expands one grayscale [value] into three RGB components.
List<int> _gray(int value) => <int>[value, value, value];

/// Resolves an indexed-colour [index] through the planar [palette].
List<int> _indexed(Uint8List palette, int index) {
  if (palette.length < 768) {
    throw const PsdFormatException('Indexed color data must contain a 768-byte palette');
  }
  return <int>[palette[index], palette[256 + index], palette[512 + index]];
}

/// Converts four 8-bit CMYK [values] into sRGB.
List<int> _cmyk(List<int> values) {
  // PSD stores CMYK channels inverted: 255 means no ink for both each colour
  // component and black.
  final double cyanInverse = values[0] / 255;
  final double magentaInverse = values[1] / 255;
  final double yellowInverse = values[2] / 255;
  final double blackInverse = values[3] / 255;
  return <int>[
    (255 * cyanInverse * blackInverse).round(),
    (255 * magentaInverse * blackInverse).round(),
    (255 * yellowInverse * blackInverse).round(),
  ];
}

/// Converts three 8-bit CIE Lab [values] into sRGB.
List<int> _lab(List<int> values) {
  final double lightness = values[0] * 100 / 255;
  final double a = values[1] - 128;
  final double b = values[2] - 128;
  final double fy = (lightness + 16) / 116;
  final double fx = fy + a / 500;
  final double fz = fy - b / 200;
  final double x = 0.96422 * _labPivot(fx);
  final double y = _labPivot(fy);
  final double z = 0.82521 * _labPivot(fz);
  final double linearRed = 3.1338561 * x - 1.6168667 * y - 0.4906146 * z;
  final double linearGreen = -0.9787684 * x + 1.9161415 * y + 0.033454 * z;
  final double linearBlue = 0.0719453 * x - 0.2289914 * y + 1.4052427 * z;
  return <int>[_srgb(linearRed), _srgb(linearGreen), _srgb(linearBlue)];
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
