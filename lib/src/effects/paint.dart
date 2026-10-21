part of '../effects.dart';

/// An RGBA color used by a layer effect.
final class PsdEffectColor {
  /// Alpha component from 0 through 255.
  final int alpha;

  /// Red component from 0 through 255.
  final int red;

  /// Green component from 0 through 255.
  final int green;

  /// Blue component from 0 through 255.
  final int blue;

  /// Opaque black.
  static const PsdEffectColor black = PsdEffectColor(alpha: 255, red: 0, green: 0, blue: 0);

  /// Creates an effect color.
  const PsdEffectColor({required this.alpha, required this.red, required this.green, required this.blue});

  /// The color packed as an ARGB integer.
  int get argb => alpha << 24 | red << 16 | green << 8 | blue;

  /// Returns an opaque sRGB color approximating [color].
  ///
  /// RGB colors are kept as they are; grayscale, CMYK, HSB and Lab colors are
  /// converted with [PsColor.toRgb]. Returns `null` for book colors and for
  /// descriptors missing a component.
  static PsdEffectColor? fromColor(PsColor color) {
    final ({double red, double green, double blue})? rgb = color.toRgb();
    if (rgb == null || !rgb.red.isFinite || !rgb.green.isFinite || !rgb.blue.isFinite) {
      return null;
    }
    return PsdEffectColor(alpha: 255, red: rgb.red.clamp(0, 255).round(), green: rgb.green.clamp(0, 255).round(), blue: rgb.blue.clamp(0, 255).round());
  }

  /// Converts this color to a Photoshop RGB color descriptor view.
  PsColor toColor() => PsColor.rgb(red: red.toDouble(), green: green.toDouble(), blue: blue.toDouble());
}

/// One color stop in a Photoshop gradient.
final class PsdGradientColorStop {
  /// Stop color.
  final PsdEffectColor color;

  /// Position from 0 through 4096.
  final int location;

  /// Midpoint percentage between this stop and the next one.
  final int midpoint;

  /// Creates a gradient color stop.
  const PsdGradientColorStop({required this.color, required this.location, this.midpoint = 50});
}

/// One opacity stop in a Photoshop gradient.
final class PsdGradientOpacityStop {
  /// Opacity percentage from 0 through 100.
  final double opacity;

  /// Position from 0 through 4096.
  final int location;

  /// Midpoint percentage between this stop and the next one.
  final int midpoint;

  /// Creates a gradient opacity stop.
  const PsdGradientOpacityStop({required this.opacity, required this.location, this.midpoint = 50});
}

/// A Photoshop custom gradient used by an effect.
final class PsdEffectGradient {
  /// Display name stored by Photoshop.
  final String name;

  /// Ordered color stops.
  final List<PsdGradientColorStop> colors;

  /// Ordered opacity stops.
  final List<PsdGradientOpacityStop> opacities;

  /// Creates a custom effect gradient.
  const PsdEffectGradient({this.name = 'Custom', required this.colors, this.opacities = const <PsdGradientOpacityStop>[]});

  /// Returns the custom stops of [gradient] in sRGB, skipping book colors.
  factory PsdEffectGradient.fromGradient(PsGradient gradient) => PsdEffectGradient(
    name: gradient.name ?? '',
    colors: [
      for (final PsGradientColorStop stop in gradient.colorStops)
        if (stop.color case final PsColor color)
          if (PsdEffectColor.fromColor(color) case final PsdEffectColor rgb)
            PsdGradientColorStop(
              color: rgb,
              location: stop.location ?? 0,
              midpoint: stop.midpoint ?? 50,
            ),
    ],
    opacities: [
      for (final PsGradientTransparencyStop stop in gradient.transparencyStops)
        PsdGradientOpacityStop(
          opacity: stop.opacity?.value ?? 100,
          location: stop.location ?? 0,
          midpoint: stop.midpoint ?? 50,
        ),
    ],
  );

  /// Converts this gradient to a Photoshop custom-stops gradient view.
  PsGradient toGradient() => PsGradient.custom(
    name: name,
    colorStops: [
      for (final PsdGradientColorStop stop in colors) PsGradientColorStop.create(color: stop.color.toColor(), location: stop.location, midpoint: stop.midpoint),
    ],
    transparencyStops: [
      for (final PsdGradientOpacityStop stop in opacities) PsGradientTransparencyStop.create(opacity: stop.opacity, location: stop.location, midpoint: stop.midpoint),
    ],
  );
}

/// A Photoshop pattern reference used by a layer effect.
final class PsdEffectPattern {
  /// Human-readable pattern name.
  final String name;

  /// Photoshop pattern UUID or identifier.
  final String id;

  /// Creates a pattern reference.
  const PsdEffectPattern({required this.name, required this.id});

  /// Converts this reference to a Photoshop pattern reference view.
  PsPatternReference toReference() => PsPatternReference.create(name: name, id: id);
}
