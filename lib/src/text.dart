import 'dart:typed_data';

import 'package:psdkit/src/binary.dart';
import 'package:psdkit/src/descriptor.dart';

/// Six-value affine transform stored by a Photoshop type tool.
final class PsdTextTransform {
  /// Horizontal scale.
  final double xx;

  /// Vertical skew.
  final double xy;

  /// Horizontal skew.
  final double yx;

  /// Vertical scale.
  final double yy;

  /// Horizontal translation.
  final double tx;

  /// Vertical translation.
  final double ty;

  /// Identity type-tool transform.
  static const PsdTextTransform identity = PsdTextTransform(xx: 1, xy: 0, yx: 0, yy: 1, tx: 0, ty: 0);

  /// Creates a type-tool affine transform.
  const PsdTextTransform({required this.xx, required this.xy, required this.yx, required this.yy, required this.tx, required this.ty});
}

/// Four signed integer bounds stored at the end of a `TySh` block.
final class PsdTextBounds {
  /// Left edge.
  final int left;

  /// Top edge.
  final int top;

  /// Right edge.
  final int right;

  /// Bottom edge.
  final int bottom;

  /// Empty bounds used by point text without a text box.
  static const PsdTextBounds zero = PsdTextBounds(left: 0, top: 0, right: 0, bottom: 0);

  /// Creates type-tool bounds.
  const PsdTextBounds({required this.left, required this.top, required this.right, required this.bottom});
}

/// Editable contents of a Photoshop `TySh` tagged block.
final class PsdTypeTool {
  /// Type-tool structure version, normally 1.
  final int version;

  /// Transform from text coordinates into layer coordinates.
  final PsdTextTransform transform;

  /// Text record version, normally 50.
  final int textVersion;

  /// Action-descriptor version for [textDescriptor], normally 16.
  final int textDescriptorVersion;

  /// Descriptor containing text, orientation, antialiasing, and engine data.
  final PsdDescriptor textDescriptor;

  /// Warp record version, normally 1.
  final int warpVersion;

  /// Action-descriptor version for [warpDescriptor], normally 16.
  final int warpDescriptorVersion;

  /// Descriptor containing text warp settings.
  final PsdDescriptor warpDescriptor;

  /// Text box or point-text bounds.
  final PsdTextBounds bounds;

  /// Bytes from newer Photoshop versions that follow the documented bounds.
  final Uint8List trailingData;

  /// Creates editable type-tool data.
  PsdTypeTool({
    required this.textDescriptor,
    required this.warpDescriptor,
    this.version = 1,
    this.transform = PsdTextTransform.identity,
    this.textVersion = 50,
    this.textDescriptorVersion = 16,
    this.warpVersion = 1,
    this.warpDescriptorVersion = 16,
    this.bounds = PsdTextBounds.zero,
    Uint8List? trailingData,
  }) : trailingData = trailingData ?? Uint8List(0);

  /// Plain Unicode text stored under the `Txt ` descriptor key.
  String get text => switch (textDescriptor.value('Txt ')) {
    PsdStringValue(:final String value) => value,
    _ => '',
  };

  /// Raw Adobe text-engine program stored under `EngineData`.
  Uint8List? get engineData => switch (textDescriptor.value('EngineData')) {
    PsdRawValue(:final Uint8List value) => value,
    _ => null,
  };

  /// Returns a copy containing [text] in both descriptor text fields.
  PsdTypeTool withText(String text) {
    PsdDescriptor descriptor = textDescriptor.withValue('Txt ', PsdStringValue(text));
    final Uint8List? engine = engineData;
    if (engine != null) {
      descriptor = descriptor.withValue('EngineData', PsdRawValue(PsdTextEngine.replaceText(engine, text)));
    }
    return PsdTypeTool(
      version: version,
      transform: transform,
      textVersion: textVersion,
      textDescriptorVersion: textDescriptorVersion,
      textDescriptor: descriptor,
      warpVersion: warpVersion,
      warpDescriptorVersion: warpDescriptorVersion,
      warpDescriptor: warpDescriptor,
      bounds: bounds,
      trailingData: trailingData,
    );
  }
}

/// Encodes and decodes the documented `TySh` structure.
abstract final class PsdTypeToolCodec {
  /// Decodes [bytes], returning `null` for malformed or unsupported data.
  static PsdTypeTool? tryDecode(Uint8List bytes) {
    try {
      return decode(bytes);
    } on FormatException {
      return null;
    }
  }

  /// Decodes one complete `TySh` tagged-block payload.
  static PsdTypeTool decode(Uint8List bytes) {
    final PsdBinaryReader reader = PsdBinaryReader(bytes);
    final int version = reader.readUint16();
    final PsdTextTransform transform = PsdTextTransform(
      xx: reader.readFloat64(),
      xy: reader.readFloat64(),
      yx: reader.readFloat64(),
      yy: reader.readFloat64(),
      tx: reader.readFloat64(),
      ty: reader.readFloat64(),
    );
    final int textVersion = reader.readUint16();
    final int textDescriptorVersion = reader.readUint32();
    late final ({PsdDescriptor descriptor, int bytesRead}) text;
    try {
      text = PsdDescriptorCodec.decodePrefix(Uint8List.sublistView(reader.bytes, reader.offset));
    } on FormatException catch (error) {
      throw FormatException('Invalid TySh text descriptor: $error');
    }
    reader.skip(text.bytesRead);
    final int warpVersion = reader.readUint16();
    final int warpDescriptorVersion = reader.readUint32();
    late final ({PsdDescriptor descriptor, int bytesRead}) warp;
    try {
      warp = PsdDescriptorCodec.decodePrefix(Uint8List.sublistView(reader.bytes, reader.offset));
    } on FormatException catch (error) {
      throw FormatException('Invalid TySh warp descriptor: $error');
    }
    reader.skip(warp.bytesRead);
    final PsdTextBounds bounds = PsdTextBounds(
      left: reader.readInt32(),
      top: reader.readInt32(),
      right: reader.readInt32(),
      bottom: reader.readInt32(),
    );
    return PsdTypeTool(
      version: version,
      transform: transform,
      textVersion: textVersion,
      textDescriptorVersion: textDescriptorVersion,
      textDescriptor: text.descriptor,
      warpVersion: warpVersion,
      warpDescriptorVersion: warpDescriptorVersion,
      warpDescriptor: warp.descriptor,
      bounds: bounds,
      trailingData: reader.readBytes(reader.remaining),
    );
  }

  /// Encodes [typeTool] as a complete `TySh` payload.
  static Uint8List encode(PsdTypeTool typeTool) {
    final PsdBinaryWriter writer = PsdBinaryWriter()
      ..writeUint16(typeTool.version)
      ..writeFloat64(typeTool.transform.xx)
      ..writeFloat64(typeTool.transform.xy)
      ..writeFloat64(typeTool.transform.yx)
      ..writeFloat64(typeTool.transform.yy)
      ..writeFloat64(typeTool.transform.tx)
      ..writeFloat64(typeTool.transform.ty)
      ..writeUint16(typeTool.textVersion)
      ..writeUint32(typeTool.textDescriptorVersion)
      ..writeBytes(PsdDescriptorCodec.encode(typeTool.textDescriptor))
      ..writeUint16(typeTool.warpVersion)
      ..writeUint32(typeTool.warpDescriptorVersion)
      ..writeBytes(PsdDescriptorCodec.encode(typeTool.warpDescriptor))
      ..writeInt32(typeTool.bounds.left)
      ..writeInt32(typeTool.bounds.top)
      ..writeInt32(typeTool.bounds.right)
      ..writeInt32(typeTool.bounds.bottom)
      ..writeBytes(typeTool.trailingData);
    return writer.takeBytes();
  }
}

/// Parses and updates Adobe text-engine data without normalizing unknown keys.
abstract final class PsdTextEngine {
  /// Replaces the PostScript string assigned to `/Text` in [engineData].
  static Uint8List replaceText(Uint8List engineData, String text) {
    final String source = String.fromCharCodes(engineData);
    final RegExp marker = RegExp(r'/Text\s*\(');
    final RegExpMatch? match = marker.firstMatch(source);
    if (match == null) return engineData;
    final int contentStart = match.end;
    final int contentEnd = _closingParenthesis(source, contentStart);
    if (contentEnd < 0) return engineData;
    final String escaped = _escapePostScript(text);
    return Uint8List.fromList('${source.substring(0, contentStart)}$escaped${source.substring(contentEnd)}'.codeUnits);
  }

  /// Locates the unescaped closing parenthesis for a PostScript string.
  static int _closingParenthesis(String source, int start) {
    int depth = 1;
    bool escaped = false;
    for (int index = start; index < source.length; index++) {
      final int unit = source.codeUnitAt(index);
      if (escaped) {
        escaped = false;
      } else if (unit == 0x5c) {
        escaped = true;
      } else if (unit == 0x28) {
        depth++;
      } else if (unit == 0x29 && --depth == 0) {
        return index;
      }
    }
    return -1;
  }

  /// Escapes [value] for a PostScript literal string.
  static String _escapePostScript(String value) => value.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)').replaceAll('\r\n', '\r').replaceAll('\n', '\r');
}
