import 'dart:typed_data';

import 'package:pscore/pscore.dart';

/// Boolean operation applied when a Photoshop subpath is combined.
enum PsdPathOperation {
  /// Excludes overlapping areas.
  exclude(code: 0),

  /// Adds the subpath to the current shape.
  combine(code: 1),

  /// Subtracts the subpath from the current shape.
  subtract(code: 2),

  /// Keeps only intersecting areas.
  intersect(code: 3);

  /// Integer stored in a subpath-length record.
  final int code;

  /// Creates an operation from its stored [code].
  const PsdPathOperation({required this.code});
}

/// A normalized two-dimensional point in Photoshop path coordinates.
final class PsdPathPoint {
  /// Horizontal coordinate, normally from zero through one.
  final double x;

  /// Vertical coordinate, normally from zero through one.
  final double y;

  /// Creates a normalized path point.
  const PsdPathPoint({required this.x, required this.y});

  /// Creates a normalized point from document pixel coordinates.
  factory PsdPathPoint.fromPixels({required double x, required double y, required int width, required int height}) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Path document dimensions must be positive');
    }
    return PsdPathPoint(x: x / width, y: y / height);
  }

  /// Converts the horizontal coordinate to pixels for [width].
  double pixelX(int width) => x * width;

  /// Converts the vertical coordinate to pixels for [height].
  double pixelY(int height) => y * height;
}

/// One cubic Bézier knot with incoming and outgoing control handles.
final class PsdBezierKnot {
  /// Incoming control handle.
  final PsdPathPoint incoming;

  /// On-curve anchor point.
  final PsdPathPoint anchor;

  /// Outgoing control handle.
  final PsdPathPoint outgoing;

  /// Whether Photoshop keeps both handles collinear while editing.
  final bool linked;

  /// Creates a Bézier knot.
  const PsdBezierKnot({required this.incoming, required this.anchor, required this.outgoing, this.linked = true});

  /// Creates a corner knot whose handles coincide with [anchor].
  const PsdBezierKnot.corner({required PsdPathPoint anchor}) : this(incoming: anchor, anchor: anchor, outgoing: anchor, linked: false);
}

/// One open or closed contour inside a Photoshop path.
final class PsdSubpath {
  /// Whether the final knot connects back to the first one.
  final bool closed;

  /// Boolean operation code, corresponding to [PsdPathOperation.code].
  final int operation;

  /// Ordered Bézier knots.
  final List<PsdBezierKnot> knots;

  /// Creates a path contour.
  const PsdSubpath({required this.closed, required this.knots, this.operation = 1});

  /// Recognized Boolean operation, or `null` for an unknown code.
  PsdPathOperation? get operationType {
    for (final PsdPathOperation value in PsdPathOperation.values) {
      if (value.code == operation) {
        return value;
      }
    }
    return null;
  }
}

/// Base type for one fixed-size Photoshop path record.
sealed class PsdPathRecord {
  /// Creates a path-record base value.
  const PsdPathRecord();

  /// Two-byte record selector.
  int get selector;
}

/// A record declaring the knot count and operation of a subpath.
final class PsdSubpathLengthRecord extends PsdPathRecord {
  /// Whether the declared subpath is closed.
  final bool closed;

  /// Number of knot records that follow.
  final int knotCount;

  /// Boolean operation code.
  final int operation;

  /// Remaining bytes retained verbatim.
  final Uint8List trailingData;

  /// Creates a subpath-length record.
  PsdSubpathLengthRecord({required this.closed, required this.knotCount, this.operation = 1, Uint8List? trailingData}) : trailingData = trailingData ?? Uint8List(20);

  @override
  int get selector => closed ? 0 : 3;
}

/// A record containing one cubic Bézier knot.
final class PsdBezierKnotRecord extends PsdPathRecord {
  /// Whether the containing subpath is closed.
  final bool closed;

  /// Knot geometry and linkage.
  final PsdBezierKnot knot;

  /// Creates a Bézier-knot record.
  const PsdBezierKnotRecord({required this.closed, required this.knot});

  @override
  int get selector => closed ? (knot.linked ? 1 : 2) : (knot.linked ? 4 : 5);
}

/// A path fill-rule record.
final class PsdPathFillRuleRecord extends PsdPathRecord {
  /// Raw fill-rule value.
  final int rule;

  /// Remaining bytes retained verbatim.
  final Uint8List trailingData;

  /// Creates a fill-rule record.
  PsdPathFillRuleRecord({this.rule = 0, Uint8List? trailingData}) : trailingData = trailingData ?? Uint8List(22);

  @override
  int get selector => 6;
}

/// A clipboard bounds and resolution path record.
final class PsdPathClipboardRecord extends PsdPathRecord {
  /// Top clipboard edge in normalized coordinates.
  final double top;

  /// Left clipboard edge in normalized coordinates.
  final double left;

  /// Bottom clipboard edge in normalized coordinates.
  final double bottom;

  /// Right clipboard edge in normalized coordinates.
  final double right;

  /// Clipboard resolution.
  final double resolution;

  /// Remaining bytes retained verbatim.
  final Uint8List trailingData;

  /// Creates a clipboard path record.
  PsdPathClipboardRecord({
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
    required this.resolution,
    Uint8List? trailingData,
  }) : trailingData = trailingData ?? Uint8List(4);

  @override
  int get selector => 7;
}

/// The initial fill state used before applying subpath operations.
final class PsdPathInitialFillRecord extends PsdPathRecord {
  /// Whether all pixels start selected.
  final bool startsWithAllPixels;

  /// Remaining bytes retained verbatim.
  final Uint8List trailingData;

  /// Creates an initial-fill record.
  PsdPathInitialFillRecord({this.startsWithAllPixels = false, Uint8List? trailingData}) : trailingData = trailingData ?? Uint8List(22);

  @override
  int get selector => 8;
}

/// An unrecognized 26-byte Photoshop path record.
final class PsdUnknownPathRecord extends PsdPathRecord {
  /// Unknown selector value.
  @override
  final int selector;

  /// Exact 24-byte record payload.
  final Uint8List data;

  /// Creates an opaque path record.
  const PsdUnknownPathRecord({required this.selector, required this.data});
}

/// An ordered Photoshop path retaining every fixed-size source record.
final class PsdVectorPath {
  /// Path records in file order.
  final List<PsdPathRecord> records;

  /// Creates a path from exact Photoshop records.
  const PsdVectorPath({required this.records});

  /// Creates a path from application-friendly [subpaths].
  factory PsdVectorPath.fromSubpaths({
    required List<PsdSubpath> subpaths,
    int fillRule = 0,
    bool startsWithAllPixels = false,
  }) => PsdVectorPath(
    records: <PsdPathRecord>[
      PsdPathFillRuleRecord(rule: fillRule),
      PsdPathInitialFillRecord(startsWithAllPixels: startsWithAllPixels),
      ..._recordsFromSubpaths(subpaths),
    ],
  );

  /// Reconstructs semantic contours from length and knot records.
  List<PsdSubpath> get subpaths {
    final List<PsdSubpath> result = <PsdSubpath>[];
    for (int index = 0; index < records.length; index++) {
      final PsdPathRecord record = records[index];
      if (record is! PsdSubpathLengthRecord) {
        continue;
      }
      final List<PsdBezierKnot> knots = <PsdBezierKnot>[];
      for (int knotIndex = 0; knotIndex < record.knotCount && index + 1 < records.length; knotIndex++) {
        final PsdPathRecord knotRecord = records[++index];
        if (knotRecord is! PsdBezierKnotRecord) {
          index--;
          break;
        }
        knots.add(knotRecord.knot);
      }
      result.add(PsdSubpath(closed: record.closed, operation: record.operation, knots: knots));
    }
    return result;
  }

  /// Initial fill state, or `false` when no record is present.
  bool get startsWithAllPixels {
    for (final PsdPathRecord record in records.reversed) {
      if (record is PsdPathInitialFillRecord) {
        return record.startsWithAllPixels;
      }
    }
    return false;
  }

  /// Returns a copy with new geometry while preserving ancillary records.
  PsdVectorPath withSubpaths(List<PsdSubpath> subpaths) => PsdVectorPath(
    records: <PsdPathRecord>[
      for (final PsdPathRecord record in records)
        if (record is! PsdSubpathLengthRecord && record is! PsdBezierKnotRecord) record,
      ..._recordsFromSubpaths(subpaths),
    ],
  );
}

/// A layer vector-mask header and its editable path.
final class PsdVectorMask {
  /// Vector-mask structure version, normally 3.
  final int version;

  /// Raw vector-mask flags.
  final int flags;

  /// Mask path geometry.
  final PsdVectorPath path;

  /// Bytes after the final complete path record.
  final Uint8List trailingData;

  /// Tagged-block key, normally `vmsk` or `vsms`.
  final String blockKey;

  /// Creates a vector mask.
  PsdVectorMask({required this.path, this.version = 3, this.flags = 0, this.blockKey = 'vmsk', Uint8List? trailingData}) : trailingData = trailingData ?? Uint8List(0);

  /// Whether the mask result is inverted.
  bool get inverted => flags & 0x01 != 0;

  /// Whether the mask is not linked to its layer.
  bool get notLinked => flags & 0x02 != 0;

  /// Whether the vector mask is disabled.
  bool get disabled => flags & 0x04 != 0;
}

/// One named document path stored as an image resource.
final class PsdNamedPath {
  /// Image-resource id, normally from 2000 through 2997.
  final int resourceId;

  /// Pascal resource name.
  final String name;

  /// Editable vector path.
  final PsdVectorPath path;

  /// Original image-resource signature.
  final String signature;

  /// Creates a named document path.
  const PsdNamedPath({required this.resourceId, required this.name, required this.path, this.signature = '8BIM'});
}

/// Encodes and decodes streams of 26-byte Photoshop path records.
abstract final class PsdVectorPathCodec {
  /// Decodes [bytes], returning `null` for malformed data.
  static PsdVectorPath? tryDecode(Uint8List bytes) {
    try {
      return decode(bytes);
    } on FormatException {
      return null;
    }
  }

  /// Decodes a complete stream of fixed-size path records.
  static PsdVectorPath decode(Uint8List bytes) {
    if (bytes.length % 26 != 0) {
      throw const FormatException('Photoshop path data must contain complete 26-byte records');
    }
    final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
    final List<PsdPathRecord> records = <PsdPathRecord>[];
    while (!reader.isAtEnd) {
      final int selector = reader.readUint16();
      final PsBinaryReader payload = reader.readReader(24);
      records.add(_readPathRecord(selector, payload));
    }
    return PsdVectorPath(records: records);
  }

  /// Encodes [path] as fixed-size Photoshop path records.
  static Uint8List encode(PsdVectorPath path) {
    final PsBinaryWriter writer = PsBinaryWriter();
    for (final PsdPathRecord record in path.records) {
      writer.writeUint16(record.selector);
      _writePathRecord(writer, record);
    }
    return writer.takeBytes();
  }
}

/// Encodes and decodes `vmsk` and `vsms` layer blocks.
abstract final class PsdVectorMaskCodec {
  /// Decodes [bytes], returning `null` for malformed data.
  static PsdVectorMask? tryDecode(Uint8List bytes, {String key = 'vmsk'}) {
    try {
      return decode(bytes, key: key);
    } on FormatException {
      return null;
    }
  }

  /// Decodes a complete vector-mask tagged-block payload.
  static PsdVectorMask decode(Uint8List bytes, {String key = 'vmsk'}) {
    final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
    final int version = reader.readUint32();
    final int flags = reader.readUint32();
    final int pathLength = reader.remaining - reader.remaining % 26;
    final PsdVectorPath path = PsdVectorPathCodec.decode(reader.readBytes(pathLength));
    return PsdVectorMask(
      version: version,
      flags: flags,
      path: path,
      blockKey: key,
      trailingData: reader.readBytes(reader.remaining),
    );
  }

  /// Encodes [mask] as a complete vector-mask payload.
  static Uint8List encode(PsdVectorMask mask) =>
      (PsBinaryWriter()
            ..writeUint32(mask.version)
            ..writeUint32(mask.flags)
            ..writeBytes(PsdVectorPathCodec.encode(mask.path))
            ..writeBytes(mask.trailingData))
          .takeBytes();
}

/// Converts semantic [subpaths] into exact length and knot records.
List<PsdPathRecord> _recordsFromSubpaths(List<PsdSubpath> subpaths) {
  final List<PsdPathRecord> records = <PsdPathRecord>[];
  for (final PsdSubpath subpath in subpaths) {
    records.add(PsdSubpathLengthRecord(closed: subpath.closed, knotCount: subpath.knots.length, operation: subpath.operation));
    for (final PsdBezierKnot knot in subpath.knots) {
      records.add(PsdBezierKnotRecord(closed: subpath.closed, knot: knot));
    }
  }
  return records;
}

/// Decodes one path record with [selector].
PsdPathRecord _readPathRecord(int selector, PsBinaryReader reader) => switch (selector) {
  0 || 3 => PsdSubpathLengthRecord(
    closed: selector == 0,
    knotCount: reader.readUint16(),
    operation: reader.readUint16(),
    trailingData: reader.readBytes(20),
  ),
  1 || 2 || 4 || 5 => PsdBezierKnotRecord(
    closed: selector == 1 || selector == 2,
    knot: PsdBezierKnot(
      incoming: _readPathPoint(reader),
      anchor: _readPathPoint(reader),
      outgoing: _readPathPoint(reader),
      linked: selector == 1 || selector == 4,
    ),
  ),
  6 => PsdPathFillRuleRecord(rule: reader.readUint16(), trailingData: reader.readBytes(22)),
  7 => PsdPathClipboardRecord(
    top: _readPathFixed(reader),
    left: _readPathFixed(reader),
    bottom: _readPathFixed(reader),
    right: _readPathFixed(reader),
    resolution: _readPathFixed(reader),
    trailingData: reader.readBytes(4),
  ),
  8 => PsdPathInitialFillRecord(startsWithAllPixels: reader.readUint16() != 0, trailingData: reader.readBytes(22)),
  _ => PsdUnknownPathRecord(selector: selector, data: reader.readBytes(24)),
};

/// Encodes one fixed-size path [record].
void _writePathRecord(PsBinaryWriter writer, PsdPathRecord record) {
  switch (record) {
    case PsdSubpathLengthRecord():
      _requireLength(record.trailingData, 20, 'subpath-length trailing data');
      writer
        ..writeUint16(record.knotCount)
        ..writeUint16(record.operation)
        ..writeBytes(record.trailingData);
    case PsdBezierKnotRecord():
      _writePathPoint(writer, record.knot.incoming);
      _writePathPoint(writer, record.knot.anchor);
      _writePathPoint(writer, record.knot.outgoing);
    case PsdPathFillRuleRecord():
      _requireLength(record.trailingData, 22, 'fill-rule trailing data');
      writer
        ..writeUint16(record.rule)
        ..writeBytes(record.trailingData);
    case PsdPathClipboardRecord():
      _requireLength(record.trailingData, 4, 'clipboard trailing data');
      _writePathFixed(writer, record.top);
      _writePathFixed(writer, record.left);
      _writePathFixed(writer, record.bottom);
      _writePathFixed(writer, record.right);
      _writePathFixed(writer, record.resolution);
      writer.writeBytes(record.trailingData);
    case PsdPathInitialFillRecord():
      _requireLength(record.trailingData, 22, 'initial-fill trailing data');
      writer
        ..writeUint16(record.startsWithAllPixels ? 1 : 0)
        ..writeBytes(record.trailingData);
    case PsdUnknownPathRecord():
      _requireLength(record.data, 24, 'unknown path record');
      writer.writeBytes(record.data);
  }
}

/// Reads one point stored in vertical-then-horizontal order.
PsdPathPoint _readPathPoint(PsBinaryReader reader) {
  final double y = _readPathFixed(reader);
  final double x = _readPathFixed(reader);
  return PsdPathPoint(x: x, y: y);
}

/// Writes one point in vertical-then-horizontal order.
void _writePathPoint(PsBinaryWriter writer, PsdPathPoint point) {
  _writePathFixed(writer, point.y);
  _writePathFixed(writer, point.x);
}

/// Reads a signed 8.24 fixed-point path coordinate.
double _readPathFixed(PsBinaryReader reader) => reader.readInt32() / 16777216;

/// Writes [value] as a signed 8.24 fixed-point coordinate.
void _writePathFixed(PsBinaryWriter writer, double value) {
  final double scaled = value * 16777216;
  if (!scaled.isFinite || scaled < -2147483648 || scaled > 2147483647) {
    throw PsWriteException(message: 'Path coordinate $value does not fit signed 8.24 fixed point');
  }
  writer.writeInt32(scaled.round());
}

/// Requires [bytes] to have the fixed [length] expected by a record.
void _requireLength(Uint8List bytes, int length, String label) {
  if (bytes.length != length) {
    throw PsWriteException(message: '$label must contain exactly $length bytes');
  }
}
