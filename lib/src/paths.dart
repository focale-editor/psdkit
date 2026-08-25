import 'dart:typed_data';

import 'package:pscore/pscore.dart';

/// Boolean operation applied when a Photoshop subpath is combined.
typedef PsdPathOperation = PsPathOperation;

/// Fill rule inferred from a Photoshop subpath's flags.
typedef PsdPathFillRule = PsPathFillRule;

/// A two-dimensional point in Photoshop path coordinates.
typedef PsdPathPoint = PsPathPoint;

/// One cubic Bézier knot with incoming and outgoing control handles.
typedef PsdBezierKnot = PsBezierKnot;

/// One open or closed contour inside a Photoshop path.
typedef PsdSubpath = PsSubpath;

/// Base type for one fixed-size Photoshop path record.
typedef PsdPathRecord = PsPathRecord;

/// A record declaring the knot count and operation of a subpath.
typedef PsdSubpathLengthRecord = PsSubpathLengthRecord;

/// A record containing one cubic Bézier knot.
typedef PsdBezierKnotRecord = PsBezierKnotRecord;

/// A path fill-rule record.
typedef PsdPathFillRuleRecord = PsPathFillRuleRecord;

/// A clipboard-bounds and resolution path record.
typedef PsdPathClipboardRecord = PsPathClipboardRecord;

/// The initial fill state used before applying subpath operations.
typedef PsdPathInitialFillRecord = PsPathInitialFillRecord;

/// An unrecognized 26-byte Photoshop path record.
typedef PsdUnknownPathRecord = PsUnknownPathRecord;

/// An ordered Photoshop path retaining every fixed-size source record.
typedef PsdVectorPath = PsVectorPath;

/// Encodes and decodes streams of 26-byte Photoshop path records.
typedef PsdVectorPathCodec = PsVectorPathCodec;

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
  PsdVectorMask({
    required this.path,
    this.version = 3,
    this.flags = 0,
    this.blockKey = 'vmsk',
    Uint8List? trailingData,
  }) : trailingData = Uint8List.fromList(trailingData ?? Uint8List(0)).asUnmodifiableView();

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
  const PsdNamedPath({
    required this.resourceId,
    required this.name,
    required this.path,
    this.signature = '8BIM',
  });
}

/// Encodes and decodes `vmsk` and `vsms` layer blocks.
abstract final class PsdVectorMaskCodec {
  /// Decodes [bytes], returning `null` for malformed data.
  static PsdVectorMask? tryDecode(
    Uint8List bytes, {
    String key = 'vmsk',
  }) {
    try {
      return decode(bytes, key: key);
    } on FormatException {
      return null;
    }
  }

  /// Decodes a complete vector-mask tagged-block payload.
  static PsdVectorMask decode(
    Uint8List bytes, {
    String key = 'vmsk',
  }) {
    final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
    final int version = reader.readUint32();
    final int flags = reader.readUint32();
    final int pathLength = reader.remaining - reader.remaining % PsVectorPathCodec.recordByteLength;
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
