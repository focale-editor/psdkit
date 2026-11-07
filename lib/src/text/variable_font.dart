part of '../text.dart';

/// An arbitrary variable-font instance named using Adobe Technical Note 5902.
///
/// Photoshop stores these coordinates in the font's PostScript name, for example
/// `SFPro_110.000wdth_673.000wght`. Named instances require the original font's
/// `fvar` table and cannot be recovered by parsing a name alone.
final class PsdVariableFontInstance {
  /// Variation PostScript prefix (OpenType name ID 25, or filtered name ID 16).
  final String prefix;

  /// Design-space coordinates keyed by their four-character OpenType axis tags.
  final Map<String, double> axes;

  /// Creates a validated arbitrary instance with immutable coordinates.
  PsdVariableFontInstance({required this.prefix, required Map<String, double> axes}) : axes = Map.unmodifiable(axes) {
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(prefix) ||
        axes.isEmpty ||
        axes.length > 32 ||
        axes.entries.any((entry) => !RegExp(r'^[A-Za-z][A-Za-z0-9 ]{3}$').hasMatch(entry.key) || !entry.value.isFinite || entry.value < -32768 || entry.value > 32767.99998474121) ||
        postScriptName.length > 127) {
      throw ArgumentError('Invalid variable-font PostScript instance');
    }
  }

  /// Parses an arbitrary instance without guessing coordinates of named styles.
  static PsdVariableFontInstance? tryParse(String name) {
    if (name.length > 127) {
      return null;
    }
    final List<String> parts = name.split('_');
    if (parts.length < 2 || !RegExp(r'^[A-Za-z0-9]+$').hasMatch(parts.first)) {
      return null;
    }
    final Map<String, double> axes = {};
    for (final String part in parts.skip(1)) {
      final RegExpMatch? match = RegExp(r'^(-?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+))([A-Za-z][A-Za-z0-9]{0,3})$').firstMatch(part);
      if (match == null) {
        return null;
      }
      final double? value = double.tryParse(match[1]!);
      final String tag = match[2]!.padRight(4);
      if (value == null || !value.isFinite || value < -32768 || value > 32767.99998474121 || axes.containsKey(tag)) {
        return null;
      }
      axes[tag] = value;
    }
    try {
      return PsdVariableFontInstance(prefix: parts.first, axes: axes);
    } on ArgumentError {
      return null;
    }
  }

  /// Deterministic name with decimal coordinates preserving 16.16 precision.
  String get postScriptName {
    final List<String> tags = axes.keys.toList()..sort();
    return '$prefix${tags.map((tag) => '_${_coordinate(axes[tag]!)}${tag.trimRight()}').join()}';
  }

  /// Finds the shortest decimal that recovers the same signed 16.16 coordinate.
  static String _coordinate(double value) {
    final int fixed = (value * 65536).round();
    for (int precision = 0; precision <= 8; precision++) {
      final String text = (fixed / 65536).toStringAsFixed(precision);
      if ((double.parse(text) * 65536).round() == fixed) {
        return text == '-0' ? '0' : text;
      }
    }
    return (fixed / 65536).toStringAsFixed(8);
  }
}
