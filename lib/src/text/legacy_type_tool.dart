part of '../text.dart';

/// One font face stored by the Photoshop 5.x `tySh` format.
final class PsdLegacyTextFace {
  /// Face identifier referenced by legacy styles.
  final int mark;

  /// Legacy Photoshop font-type value.
  final int fontType;

  /// Font name stored as a Pascal byte string.
  final String fontName;

  /// Font family name stored as a Pascal byte string.
  final String fontFamilyName;

  /// Font style name stored as a Pascal byte string.
  final String fontStyleName;

  /// Legacy script identifier.
  final int script;

  /// Variable-font design-axis values in their stored integer form.
  final List<int> designVector;

  /// Creates a legacy font face.
  PsdLegacyTextFace({
    required this.mark,
    required this.fontType,
    required this.fontName,
    required this.fontFamilyName,
    required this.fontStyleName,
    required this.script,
    List<int> designVector = const <int>[],
  }) : designVector = List<int>.unmodifiable(designVector);
}

/// One style record stored by the Photoshop 5.x `tySh` format.
final class PsdLegacyTextStyle {
  /// Style identifier referenced by legacy line records.
  final int mark;

  /// Font-face identifier from [PsdLegacyTextFace.mark].
  final int faceMark;

  /// Font size in the original stored integer representation.
  final int size;

  /// Tracking in the original stored integer representation.
  final int tracking;

  /// Kerning in the original stored integer representation.
  final int kerning;

  /// Leading in the original stored integer representation.
  final int leading;

  /// Baseline shift in the original stored integer representation.
  final int baselineShift;

  /// Whether automatic kerning is enabled.
  final bool automaticKerning;

  /// Undocumented byte present in Photoshop 5.x style records.
  final int compatibilityByte;

  /// Whether glyphs rotate upward or downward.
  final bool rotate;

  /// Creates a legacy style record.
  const PsdLegacyTextStyle({
    required this.mark,
    required this.faceMark,
    required this.size,
    required this.tracking,
    required this.kerning,
    required this.leading,
    required this.baselineShift,
    required this.automaticKerning,
    required this.compatibilityByte,
    required this.rotate,
  });
}

/// One line record stored by the Photoshop 5.x `tySh` format.
final class PsdLegacyTextLine {
  /// Character count assigned to this line.
  final int characterCount;

  /// Legacy orientation value.
  final int orientation;

  /// Legacy alignment value.
  final int alignment;

  /// Double-byte character value associated with the line.
  final int actualCharacter;

  /// Style mark associated with the line.
  final int style;

  /// Creates a legacy line record.
  const PsdLegacyTextLine({
    required this.characterCount,
    required this.orientation,
    required this.alignment,
    required this.actualCharacter,
    required this.style,
  });
}

/// Color value stored by the Photoshop 5.x `tySh` format.
final class PsdLegacyTextColor {
  /// Photoshop color-space identifier.
  final int colorSpace;

  /// Four unsigned 16-bit color components.
  final List<int> components;

  /// Creates a legacy text color.
  PsdLegacyTextColor({
    required this.colorSpace,
    required List<int> components,
  }) : components = List<int>.unmodifiable(components);
}

/// Complete structural representation of Photoshop 5.x `tySh` data.
///
/// The historical format does not expose a documented contiguous text string;
/// its original face, style, line, and color records are retained instead.
final class PsdLegacyTypeTool {
  /// Legacy type-tool version, normally 1.
  final int version;

  /// Transform from text coordinates into layer coordinates.
  final PsdTextTransform transform;

  /// Legacy font-information version, normally 6.
  final int fontVersion;

  /// Font faces referenced by [styles].
  final List<PsdLegacyTextFace> faces;

  /// Legacy character styles.
  final List<PsdLegacyTextStyle> styles;

  /// Legacy text-type value.
  final int type;

  /// Legacy scaling factor.
  final int scalingFactor;

  /// Total character count.
  final int characterCount;

  /// Horizontal placement in the original stored representation.
  final int horizontalPlacement;

  /// Vertical placement in the original stored representation.
  final int verticalPlacement;

  /// Start of the legacy selection.
  final int selectionStart;

  /// End of the legacy selection.
  final int selectionEnd;

  /// Legacy line records.
  final List<PsdLegacyTextLine> lines;

  /// Legacy text color.
  final PsdLegacyTextColor color;

  /// Whether antialiasing is enabled.
  final bool antiAlias;

  /// Undocumented bytes following the published structure.
  final Uint8List trailingData;

  /// Creates a complete legacy type-tool record.
  PsdLegacyTypeTool({
    required List<PsdLegacyTextFace> faces,
    required List<PsdLegacyTextStyle> styles,
    required this.type,
    required this.scalingFactor,
    required this.characterCount,
    required this.horizontalPlacement,
    required this.verticalPlacement,
    required this.selectionStart,
    required this.selectionEnd,
    required List<PsdLegacyTextLine> lines,
    required this.color,
    required this.antiAlias,
    this.version = 1,
    this.transform = PsdTextTransform.identity,
    this.fontVersion = 6,
    Uint8List? trailingData,
  }) : faces = List<PsdLegacyTextFace>.unmodifiable(faces),
       styles = List<PsdLegacyTextStyle>.unmodifiable(styles),
       lines = List<PsdLegacyTextLine>.unmodifiable(lines),
       trailingData = trailingData ?? Uint8List(0);
}

/// Encodes and decodes the published Photoshop 5.x `tySh` structure.
abstract final class PsdLegacyTypeToolCodec {
  /// Decodes [bytes], returning `null` for malformed legacy data.
  static PsdLegacyTypeTool? tryDecode(Uint8List bytes) {
    try {
      return decode(bytes);
    } on FormatException {
      return null;
    }
  }

  /// Decodes one complete Photoshop 5.x `tySh` payload.
  static PsdLegacyTypeTool decode(Uint8List bytes) {
    final PsBinaryReader reader = PsBinaryReader(bytes: bytes);
    final int version = reader.readUint16();
    final PsdTextTransform transform = PsdTextTransform(
      xx: reader.readFloat64(),
      xy: reader.readFloat64(),
      yx: reader.readFloat64(),
      yy: reader.readFloat64(),
      tx: reader.readFloat64(),
      ty: reader.readFloat64(),
    );
    final int fontVersion = reader.readUint16();
    final int faceCount = reader.readUint16();
    if (faceCount > reader.remaining ~/ 15) {
      throw const FormatException('Legacy type-tool face count exceeds its payload');
    }
    final List<PsdLegacyTextFace> faces = <PsdLegacyTextFace>[];
    for (int index = 0; index < faceCount; index++) {
      final int mark = reader.readInt16();
      final int fontType = reader.readInt32();
      final String fontName = _readPascalString(reader);
      final String fontFamilyName = _readPascalString(reader);
      final String fontStyleName = _readPascalString(reader);
      final int script = reader.readInt16();
      final int designAxisCount = reader.readInt32();
      if (designAxisCount < 0 || designAxisCount > reader.remaining ~/ 4) {
        throw const FormatException('Legacy type-tool design-axis count exceeds its payload');
      }
      faces.add(
        PsdLegacyTextFace(
          mark: mark,
          fontType: fontType,
          fontName: fontName,
          fontFamilyName: fontFamilyName,
          fontStyleName: fontStyleName,
          script: script,
          designVector: <int>[
            for (int axis = 0; axis < designAxisCount; axis++) reader.readInt32(),
          ],
        ),
      );
    }
    final int styleCount = reader.readUint16();
    if (styleCount > reader.remaining ~/ 27) {
      throw const FormatException('Legacy type-tool style count exceeds its payload');
    }
    final List<PsdLegacyTextStyle> styles = <PsdLegacyTextStyle>[
      for (int index = 0; index < styleCount; index++)
        PsdLegacyTextStyle(
          mark: reader.readInt16(),
          faceMark: reader.readInt16(),
          size: reader.readInt32(),
          tracking: reader.readInt32(),
          kerning: reader.readInt32(),
          leading: reader.readInt32(),
          baselineShift: reader.readInt32(),
          automaticKerning: reader.readUint8() != 0,
          compatibilityByte: reader.readUint8(),
          rotate: reader.readUint8() != 0,
        ),
    ];
    final int type = reader.readInt16();
    final int scalingFactor = reader.readInt32();
    final int characterCount = reader.readInt32();
    final int horizontalPlacement = reader.readInt32();
    final int verticalPlacement = reader.readInt32();
    final int selectionStart = reader.readInt32();
    final int selectionEnd = reader.readInt32();
    final int lineCount = reader.readUint16();
    if (lineCount > reader.remaining ~/ 12) {
      throw const FormatException('Legacy type-tool line count exceeds its payload');
    }
    final List<PsdLegacyTextLine> lines = <PsdLegacyTextLine>[
      for (int index = 0; index < lineCount; index++)
        PsdLegacyTextLine(
          characterCount: reader.readInt32(),
          orientation: reader.readInt16(),
          alignment: reader.readInt16(),
          actualCharacter: reader.readUint16(),
          style: reader.readInt16(),
        ),
    ];
    final PsdLegacyTextColor color = PsdLegacyTextColor(
      colorSpace: reader.readUint16(),
      components: <int>[
        for (int index = 0; index < 4; index++) reader.readUint16(),
      ],
    );
    final bool antiAlias = reader.readUint8() != 0;
    return PsdLegacyTypeTool(
      version: version,
      transform: transform,
      fontVersion: fontVersion,
      faces: faces,
      styles: styles,
      type: type,
      scalingFactor: scalingFactor,
      characterCount: characterCount,
      horizontalPlacement: horizontalPlacement,
      verticalPlacement: verticalPlacement,
      selectionStart: selectionStart,
      selectionEnd: selectionEnd,
      lines: lines,
      color: color,
      antiAlias: antiAlias,
      trailingData: reader.readBytes(reader.remaining),
    );
  }

  /// Encodes [typeTool] as a complete Photoshop 5.x `tySh` payload.
  static Uint8List encode(PsdLegacyTypeTool typeTool) {
    if (typeTool.faces.length > 0xffff || typeTool.styles.length > 0xffff || typeTool.lines.length > 0xffff) {
      throw const PsWriteException(message: 'Legacy type-tool collections cannot exceed 65535 entries');
    }
    if (typeTool.color.components.length != 4) {
      throw const PsWriteException(message: 'A legacy type-tool color must contain four components');
    }
    final PsBinaryWriter writer = PsBinaryWriter()
      ..writeUint16(typeTool.version)
      ..writeFloat64(typeTool.transform.xx)
      ..writeFloat64(typeTool.transform.xy)
      ..writeFloat64(typeTool.transform.yx)
      ..writeFloat64(typeTool.transform.yy)
      ..writeFloat64(typeTool.transform.tx)
      ..writeFloat64(typeTool.transform.ty)
      ..writeUint16(typeTool.fontVersion)
      ..writeUint16(typeTool.faces.length);
    for (final PsdLegacyTextFace face in typeTool.faces) {
      writer
        ..writeInt16(face.mark)
        ..writeInt32(face.fontType);
      _writePascalString(writer, face.fontName);
      _writePascalString(writer, face.fontFamilyName);
      _writePascalString(writer, face.fontStyleName);
      writer
        ..writeInt16(face.script)
        ..writeInt32(face.designVector.length);
      face.designVector.forEach(writer.writeInt32);
    }
    writer.writeUint16(typeTool.styles.length);
    for (final PsdLegacyTextStyle style in typeTool.styles) {
      writer
        ..writeInt16(style.mark)
        ..writeInt16(style.faceMark)
        ..writeInt32(style.size)
        ..writeInt32(style.tracking)
        ..writeInt32(style.kerning)
        ..writeInt32(style.leading)
        ..writeInt32(style.baselineShift)
        ..writeUint8(style.automaticKerning ? 1 : 0)
        ..writeUint8(style.compatibilityByte)
        ..writeUint8(style.rotate ? 1 : 0);
    }
    writer
      ..writeInt16(typeTool.type)
      ..writeInt32(typeTool.scalingFactor)
      ..writeInt32(typeTool.characterCount)
      ..writeInt32(typeTool.horizontalPlacement)
      ..writeInt32(typeTool.verticalPlacement)
      ..writeInt32(typeTool.selectionStart)
      ..writeInt32(typeTool.selectionEnd)
      ..writeUint16(typeTool.lines.length);
    for (final PsdLegacyTextLine line in typeTool.lines) {
      writer
        ..writeInt32(line.characterCount)
        ..writeInt16(line.orientation)
        ..writeInt16(line.alignment)
        ..writeUint16(line.actualCharacter)
        ..writeInt16(line.style);
    }
    writer.writeUint16(typeTool.color.colorSpace);
    typeTool.color.components.forEach(writer.writeUint16);
    writer
      ..writeUint8(typeTool.antiAlias ? 1 : 0)
      ..writeBytes(typeTool.trailingData);
    return writer.takeBytes();
  }
}

/// Reads an unpadded one-byte-length Pascal string.
String _readPascalString(PsBinaryReader reader) => reader.readString(reader.readUint8());

/// Writes an unpadded one-byte-length Pascal string.
void _writePascalString(PsBinaryWriter writer, String value) {
  if (value.length > 0xff || value.codeUnits.any((unit) => unit > 0xff)) {
    throw const PsWriteException(message: 'Legacy type-tool names must fit a 255-byte string');
  }
  writer
    ..writeUint8(value.length)
    ..writeString(value);
}
