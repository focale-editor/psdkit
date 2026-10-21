part of '../adjustments.dart';

/// One colour stop of a gradient map, in Photoshop's legacy colour layout.
final class PsdGradientMapColorStop {
  /// Position along the gradient, from 0 to the map's [PsdGradientMapAdjustment.smoothness] scale, normally 4096.
  final int location;

  /// Transition midpoint in percent.
  final int midpoint;

  /// Colour-space identifier of [components], as in Photoshop colour structures: 0 is RGB.
  final int colorSpace;

  /// Four 16-bit colour components.
  final List<int> components;

  /// Stop kind: 0 for a user colour, 1 for the foreground, 2 for the background colour.
  final int kind;

  /// Creates a colour stop.
  PsdGradientMapColorStop({
    required this.location,
    this.midpoint = 50,
    this.colorSpace = 0,
    required List<int> components,
    this.kind = 0,
  }) : components = List<int>.unmodifiable(components);

  /// Creates a user stop from 8-bit RGB components.
  factory PsdGradientMapColorStop.rgb({required int location, required int red, required int green, required int blue, int midpoint = 50}) =>
      PsdGradientMapColorStop(location: location, midpoint: midpoint, components: [red * 257, green * 257, blue * 257, 0]);
}

/// One opacity stop of a gradient map.
final class PsdGradientMapOpacityStop {
  /// Position along the gradient, on the same scale as colour stops.
  final int location;

  /// Transition midpoint in percent.
  final int midpoint;

  /// Opacity from 0 to 255.
  final int opacity;

  /// Creates an opacity stop.
  const PsdGradientMapOpacityStop({required this.location, this.midpoint = 50, this.opacity = 255});
}

/// Gradient-map settings stored in a `grdm` block.
///
/// The colour and opacity stops use the record layout of legacy `.grd`
/// libraries. Noise parameters are always present, even for a solid gradient.
final class PsdGradientMapAdjustment extends PsdAdjustment {
  /// Format version: 1, or 3 when [method] is stored.
  final int version;

  /// Whether the gradient is reversed.
  final bool reverse;

  /// Whether the result is dithered.
  final bool dither;

  /// Interpolation method signature, such as `Gcsp`, stored by version 3.
  final String? method;

  /// Gradient name.
  final String name;

  /// Colour stops in source order.
  final List<PsdGradientMapColorStop> colorStops;

  /// Opacity stops in source order.
  final List<PsdGradientMapOpacityStop> opacityStops;

  /// Smoothness, and the scale of stop locations, normally 4096.
  final int smoothness;

  /// Whether the gradient is generated from noise instead of its stops.
  final bool noise;

  /// Noise random seed.
  final int randomSeed;

  /// Whether noise adds transparency.
  final bool showsTransparency;

  /// Whether noise restricts colours to printable values.
  final bool restrictsColors;

  /// Noise roughness from 0 to 4096.
  final int roughness;

  /// Noise colour model: 0 RGB, 1 HSB, or 2 Lab, as Photoshop numbers them.
  final int colorModel;

  /// Four noise minimum channel values.
  final List<int> minimumValues;

  /// Four noise maximum channel values.
  final List<int> maximumValues;

  /// Uninterpreted bytes following the documented fields.
  final Uint8List trailingData;

  /// Creates gradient-map settings.
  PsdGradientMapAdjustment({
    this.version = 1,
    this.reverse = false,
    this.dither = false,
    this.method,
    this.name = '',
    required List<PsdGradientMapColorStop> colorStops,
    List<PsdGradientMapOpacityStop> opacityStops = const [PsdGradientMapOpacityStop(location: 0), PsdGradientMapOpacityStop(location: 4096)],
    this.smoothness = 4096,
    this.noise = false,
    this.randomSeed = 0,
    this.showsTransparency = false,
    this.restrictsColors = false,
    this.roughness = 2048,
    this.colorModel = 3,
    List<int> minimumValues = const [0, 0, 0, 0],
    List<int> maximumValues = const [0x8000, 0x8000, 0x8000, 0x8000],
    Uint8List? trailingData,
  }) : colorStops = List<PsdGradientMapColorStop>.unmodifiable(colorStops),
       opacityStops = List<PsdGradientMapOpacityStop>.unmodifiable(opacityStops),
       minimumValues = List<int>.unmodifiable(minimumValues),
       maximumValues = List<int>.unmodifiable(maximumValues),
       trailingData = trailingData ?? Uint8List(2);

  @override
  String get blockKey => 'grdm';

  @override
  PsdAdjustmentType get type => PsdAdjustmentType.gradientMap;
}
