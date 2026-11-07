part of '../text.dart';

/// A continuous cubic baseline in the coordinate system of its text tool.
///
/// Each segment has eight coordinates (`x0 y0 x1 y1 x2 y2 x3 y3`). Range
/// positions use `segment index + Bézier parameter`, not a fraction of length.
/// Null range positions retain Photoshop's default start/end markers.
final class PsdTextPath {
  /// Cubic control coordinates, with a repeated endpoint between segments.
  final List<double> controlPoints;

  /// Start marker in segment/parameter units, or the default start.
  final double? start;

  /// End marker in segment/parameter units, or the complete path.
  final double? end;

  /// Whether the text runs on the reverse side of the baseline.
  final bool reversed;

  /// Creates bounded, continuous geometry in text-local coordinates.
  PsdTextPath({required List<double> controlPoints, this.start, this.end, this.reversed = false}) : controlPoints = List.unmodifiable(controlPoints) {
    if (controlPoints.isEmpty || controlPoints.length % 8 != 0 || controlPoints.length > 4096 * 8 || controlPoints.any((value) => !value.isFinite || value.abs() > 1e9)) {
      throw ArgumentError('Invalid text-path control points');
    }
    for (int index = 8; index < controlPoints.length; index += 8) {
      if ((controlPoints[index] - controlPoints[index - 2]).abs() > 1e-3 || (controlPoints[index + 1] - controlPoints[index - 1]).abs() > 1e-3) {
        throw ArgumentError('Text paths must be continuous');
      }
    }
    final int count = controlPoints.length ~/ 8;
    if ([start, end].any((value) => value != null && (!value.isFinite || value < 0 || value > count)) || start != null && end != null && end! < start!) {
      throw ArgumentError('Invalid text-path range');
    }
  }
}

/// Resolves one frame through the object's view, never through its layer order.
PsdTextContent _applyGlobalFrame(_PsdEngineDictionary root, Object? object, PsdTextContent content) {
  final List<Object?>? references = _list(_globalPath(object, ['1', '0']));
  final List<Object?>? frames = _list(_globalPath(root, ['0', '8', '0']));
  if (references == null || frames == null) {
    return content;
  }
  if (references.length != 1) {
    return content.copyWith(hasUnsupportedGeometry: true);
  }
  final int? index = _integer(_globalPath(references.single, ['0']));
  if (index == null || index < 0 || index >= frames.length) {
    return content.copyWith(hasUnsupportedGeometry: true);
  }
  final Object? frame = _globalPath(frames[index], ['0']);
  final int kind = _integer(_globalPath(frame, ['2', '0'])) ?? 0;
  if (kind == 0) {
    return content;
  }
  if (kind == 1) {
    final List<double>? range = _pathNumbers(_globalPath(frame, ['2', '6']));
    return range != null && range.length == 2 && range.every((value) => value == -2) ? content : content.copyWith(hasUnsupportedGeometry: true);
  }
  if (kind != 2) {
    return content.copyWith(hasUnsupportedGeometry: true);
  }
  final PsdTextPath? path = _readGlobalPath(frame);
  return content.copyWith(path: path, hasUnsupportedGeometry: path == null);
}

/// Reads finite numeric arrays without silently repairing malformed geometry.
List<double>? _pathNumbers(Object? value) {
  final List<Object?>? values = _list(value);
  return values != null && values.every((item) => item is num && item.isFinite) ? [for (final Object? item in values) (item! as num).toDouble()] : null;
}

/// Converts Photoshop frame coordinates into the local space of `TySh`.
PsdTextPath? _readGlobalPath(Object? frame) {
  final List<double>? points = _pathNumbers(_globalPath(frame, ['1', '0']));
  final Object? rawMatrix = _globalPath(frame, ['2', '2']);
  final List<double>? matrix = rawMatrix == null ? [1, 0, 0, 1, 0, 0] : _pathNumbers(rawMatrix);
  final Object? rawRange = _globalPath(frame, ['2', '6']);
  final List<double>? range = rawRange == null ? [-1, -1] : _pathNumbers(rawRange);
  final _PsdEngineDictionary? settings = _dictionary(_globalPath(frame, ['2', '11']));
  final Object? reversed = settings?['0'];
  // Non-neutral spacing, effects or baseline alignment need their own mapping.
  if (points == null ||
      points.length % 8 != 0 ||
      points.length > 32768 ||
      matrix == null ||
      matrix.length != 6 ||
      range == null ||
      range.length != 2 ||
      (matrix[0] * matrix[3] - matrix[1] * matrix[2]).abs() < 1e-12 ||
      reversed != null && reversed is! bool ||
      settings != null && settings.values.entries.any((entry) => entry.key != '0' && (!const {'3', '5', '7'}.contains(entry.key) || entry.value != 0 && entry.value != false)) ||
      _globalPath(frame, ['2', '10']) != null) {
    return null;
  }
  final List<double> transformed = [];
  for (int index = 0; index < points.length; index += 2) {
    transformed.addAll([matrix[0] * points[index] + matrix[2] * points[index + 1] + matrix[4], matrix[1] * points[index] + matrix[3] * points[index + 1] + matrix[5]]);
  }
  try {
    return PsdTextPath(controlPoints: transformed, start: range[0] == -1 ? null : range[0], end: range[1] == -1 ? null : range[1], reversed: reversed == true);
  } on ArgumentError {
    return null;
  }
}
