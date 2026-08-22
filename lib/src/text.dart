import 'dart:typed_data';

import 'package:psdkit/src/binary.dart';
import 'package:psdkit/src/descriptor.dart';

/// Direction in which Photoshop lays out a text layer.
enum PsdTextOrientation {
  /// Text advances horizontally.
  horizontal,

  /// Text advances vertically.
  vertical,
}

/// Paragraph alignment stored by the Adobe text engine.
enum PsdTextJustification {
  /// Aligns text to the leading edge.
  left,

  /// Centers text.
  center,

  /// Aligns text to the trailing edge.
  right,

  /// Justifies all lines except the last one, aligned left.
  justifyLeft,

  /// Justifies all lines except the last one, centered.
  justifyCenter,

  /// Justifies all lines except the last one, aligned right.
  justifyRight,

  /// Justifies every line.
  justifyAll,
}

/// An RGBA color used by a Photoshop text style.
final class PsdTextColor {
  /// Alpha component from 0 through 255.
  final int alpha;

  /// Red component from 0 through 255.
  final int red;

  /// Green component from 0 through 255.
  final int green;

  /// Blue component from 0 through 255.
  final int blue;

  /// Creates a text color.
  const PsdTextColor({required this.alpha, required this.red, required this.green, required this.blue});

  /// The color packed as an ARGB integer.
  int get argb => alpha << 24 | red << 16 | green << 8 | blue;
}

/// Formatting applied to a range of Photoshop text.
final class PsdTextStyle {
  /// PostScript or Photoshop font name, when known.
  final String? fontFamily;

  /// Font size in text points, when explicitly stored.
  final double? fontSize;

  /// Foreground color, when explicitly stored.
  final PsdTextColor? color;

  /// Additional tracking in thousandths of an em.
  final double? tracking;

  /// Explicit line height, or `null` for automatic leading.
  final double? lineHeight;

  /// Whether Photoshop synthesizes a bold face.
  final bool fauxBold;

  /// Whether Photoshop synthesizes an italic face.
  final bool fauxItalic;

  /// Whether the range is underlined.
  final bool underline;

  /// Whether the range is struck through.
  final bool strikethrough;

  /// Creates a text style.
  const PsdTextStyle({
    this.fontFamily,
    this.fontSize,
    this.color,
    this.tracking,
    this.lineHeight,
    this.fauxBold = false,
    this.fauxItalic = false,
    this.underline = false,
    this.strikethrough = false,
  });
}

/// A UTF-16 code-unit range sharing one text style.
final class PsdTextStyleRun {
  /// Inclusive start offset in [PsdTextContent.text].
  final int start;

  /// Number of UTF-16 code units in this range.
  final int length;

  /// Formatting carried by this range.
  final PsdTextStyle style;

  /// Creates a text style range.
  const PsdTextStyleRun({required this.start, required this.length, required this.style});
}

/// A UTF-16 code-unit range sharing one paragraph style.
final class PsdTextParagraph {
  /// Inclusive start offset in [PsdTextContent.text].
  final int start;

  /// Number of UTF-16 code units in this paragraph range.
  final int length;

  /// Paragraph alignment.
  final PsdTextJustification justification;

  /// Creates a paragraph range.
  const PsdTextParagraph({required this.start, required this.length, required this.justification});
}

/// Semantic, application-friendly representation of a Photoshop text layer.
final class PsdTextContent {
  /// Plain text using carriage returns as Photoshop line separators.
  final String text;

  /// Text layout direction.
  final PsdTextOrientation orientation;

  /// Character style ranges extracted from `EngineData`.
  final List<PsdTextStyleRun> styleRuns;

  /// Paragraph ranges extracted from `EngineData`.
  final List<PsdTextParagraph> paragraphs;

  /// Creates semantic text-layer contents.
  const PsdTextContent({required this.text, required this.orientation, this.styleRuns = const [], this.paragraphs = const []});

  /// Returns the most specific style covering [offset], when available.
  PsdTextStyle? styleAt(int offset) {
    for (final PsdTextStyleRun run in styleRuns.reversed) {
      if (offset >= run.start && offset < run.start + run.length) {
        return run.style;
      }
    }
    return null;
  }
}

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

  /// Creates a complete editable type-tool record from semantic [content].
  factory PsdTypeTool.fromText({
    required PsdTextContent content,
    PsdTextTransform transform = PsdTextTransform.identity,
    PsdTextBounds bounds = PsdTextBounds.zero,
  }) => PsdTypeTool(
    transform: transform,
    bounds: bounds,
    textDescriptor: _createTextDescriptor(content, bounds),
    warpDescriptor: _createWarpDescriptor(content.orientation),
  );

  /// Plain Unicode text stored under the `Txt ` descriptor key.
  String get text => switch (textDescriptor.value('Txt ')) {
    PsdStringValue(:final String value) => _withoutTerminalNull(value),
    _ => '',
  };

  /// Layout direction stored by the type-tool descriptor.
  PsdTextOrientation get orientation => switch (textDescriptor.value('Ornt')) {
    PsdEnumeratedValue(:final String value) when value == 'Vrtc' => PsdTextOrientation.vertical,
    _ => PsdTextOrientation.horizontal,
  };

  /// Semantic text, styles, and paragraphs suitable for application models.
  PsdTextContent get content => PsdTextEngine.decode(engineData, fallbackText: text, orientation: orientation);

  /// Raw Adobe text-engine program stored under `EngineData`.
  Uint8List? get engineData => switch (textDescriptor.value('EngineData')) {
    PsdRawValue(:final Uint8List value) => value,
    _ => null,
  };

  /// Returns a copy containing [text] in both descriptor text fields.
  PsdTypeTool withText(String text) {
    final String normalized = text.replaceAll('\r\n', '\r').replaceAll('\n', '\r');
    PsdDescriptor descriptor = textDescriptor.withValue('Txt ', PsdStringValue('$normalized\u0000'));
    final Uint8List? engine = engineData;
    if (engine != null) {
      descriptor = descriptor.withValue('EngineData', PsdRawValue(PsdTextEngine.replaceText(engine, normalized)));
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

  /// Returns a semantic rewrite of this type tool using [content].
  ///
  /// Unlike [withText], this regenerates `EngineData`; use it when styles or
  /// paragraph properties changed and retain the original instance otherwise.
  PsdTypeTool withContent(PsdTextContent content) {
    final PsdDescriptor descriptor = textDescriptor
        .withValue('Txt ', PsdStringValue('${content.text.replaceAll('\r\n', '\r').replaceAll('\n', '\r')}\u0000'))
        .withValue(
          'Ornt',
          PsdEnumeratedValue(typeId: 'Ornt', value: content.orientation == PsdTextOrientation.vertical ? 'Vrtc' : 'Hrzn'),
        )
        .withValue('EngineData', PsdRawValue(PsdTextEngine.encode(content)));
    final PsdDescriptor warp = warpDescriptor.withValue(
      'warpRotate',
      PsdEnumeratedValue(typeId: 'Ornt', value: content.orientation == PsdTextOrientation.vertical ? 'Vrtc' : 'Hrzn'),
    );
    return PsdTypeTool(
      version: version,
      transform: transform,
      textVersion: textVersion,
      textDescriptorVersion: textDescriptorVersion,
      textDescriptor: descriptor,
      warpVersion: warpVersion,
      warpDescriptorVersion: warpDescriptorVersion,
      warpDescriptor: warp,
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
  /// Extracts semantic text information from opaque Adobe [engineData].
  static PsdTextContent decode(Uint8List? engineData, {required String fallbackText, required PsdTextOrientation orientation}) {
    if (engineData == null) {
      return PsdTextContent(text: fallbackText, orientation: orientation);
    }
    try {
      final Object? rootValue = _PsdEngineParser(engineData).parse();
      final _PsdEngineDictionary? root = _dictionary(rootValue);
      final _PsdEngineDictionary? engine = _dictionary(root?['EngineDict']);
      final _PsdEngineDictionary? editor = _dictionary(engine?['Editor']);
      final String text = _decodeEngineString(editor?['Text']) ?? fallbackText;
      final String logicalText = _withoutTerminalNull(text);
      final List<String> fonts = _readFonts(_dictionary(root?['ResourceDict']));
      return PsdTextContent(
        text: logicalText,
        orientation: orientation,
        styleRuns: _readStyleRuns(engine, fonts, logicalText.length),
        paragraphs: _readParagraphs(engine, logicalText.length),
      );
    } on FormatException {
      return PsdTextContent(text: fallbackText, orientation: orientation);
    }
  }

  /// Encodes semantic [content] as self-contained Adobe text-engine data.
  static Uint8List encode(PsdTextContent content) {
    final String text = content.text.replaceAll('\r\n', '\r').replaceAll('\n', '\r');
    final List<_PsdNormalizedStyleRun> styles = _normalizeStyles(content.styleRuns, text.length);
    final List<_PsdNormalizedParagraph> paragraphs = _normalizeParagraphs(content.paragraphs, text.length);
    final List<String> fonts = <String>[];
    for (final _PsdNormalizedStyleRun run in styles) {
      final String font = run.style.fontFamily ?? 'ArialMT';
      if (!fonts.contains(font)) {
        fonts.add(font);
      }
    }
    final _PsdEngineWriter writer = _PsdEngineWriter()
      ..ascii('<< /EngineDict << /Editor << /Text ')
      ..unicodeString(text, terminalNull: true)
      ..ascii(' >> /ParagraphRun << /RunArray [ ');
    for (final _PsdNormalizedParagraph paragraph in paragraphs) {
      writer.ascii(
        '<< /ParagraphSheet << /DefaultStyleSheet 0 /Properties << '
        '/Justification ${paragraph.justification.index} >> >> >> ',
      );
    }
    writer.ascii('] /RunLengthArray [ ${paragraphs.map((run) => run.length).join(' ')} ] >> /StyleRun << /RunArray [ ');
    for (final _PsdNormalizedStyleRun run in styles) {
      final PsdTextStyle style = run.style;
      final PsdTextColor color = style.color ?? const PsdTextColor(alpha: 255, red: 0, green: 0, blue: 0);
      writer.ascii(
        '<< /StyleSheet << /StyleSheetData << '
        '/Font ${fonts.indexOf(style.fontFamily ?? 'ArialMT')} '
        '/FontSize ${_engineNumber(style.fontSize ?? 12)} '
        '/FauxBold ${style.fauxBold} /FauxItalic ${style.fauxItalic} '
        '/Underline ${style.underline ? 1 : 0} /Strikethrough ${style.strikethrough ? 1 : 0} '
        '/Tracking ${_engineNumber(style.tracking ?? 0)} '
        '/AutoLeading ${style.lineHeight == null} ',
      );
      if (style.lineHeight != null) {
        writer.ascii('/Leading ${_engineNumber(style.lineHeight!)} ');
      }
      writer.ascii(
        '/FillColor << /Type 1 /Values [ ${_engineColor(color.alpha)} ${_engineColor(color.red)} '
        '${_engineColor(color.green)} ${_engineColor(color.blue)} ] >> >> >> >> ',
      );
    }
    writer.ascii(
      '] /RunLengthArray [ ${styles.map((run) => run.length).join(' ')} ] >> '
      '/GridInfo << /GridIsOn false /ShowGrid false /GridSize 18 /GridLeading 22.8 /GridColor << /Type 1 /Values [ 0 0 0 0 ] >> >> '
      '>> /ResourceDict << /TheNormalStyleSheet 0 /TheNormalParagraphSheet 0 /FontSet [ ',
    );
    for (final String font in fonts) {
      writer
        ..ascii('<< /Name ')
        ..unicodeString(font)
        ..ascii(' /Script 0 /FontType 0 /Synthetic 0 >> ');
    }
    writer.ascii('] >> >>');
    return writer.takeBytes();
  }

  /// Replaces the PostScript string assigned to `/Text` in [engineData].
  static Uint8List replaceText(Uint8List engineData, String text) {
    final ({int start, int end, Uint8List value})? target = _findTextString(engineData);
    if (target == null) {
      return engineData;
    }
    final int oldLength = _withoutTerminalNull(_decodeEngineString(_PsdEngineString(target.value)) ?? '').length;
    final Uint8List encoded = _encodeEngineString(text, target.value);
    final BytesBuilder output = BytesBuilder(copy: false)
      ..add(Uint8List.sublistView(engineData, 0, target.start))
      ..add(_escapePostScript(encoded))
      ..add(Uint8List.sublistView(engineData, target.end));
    Uint8List updated = output.takeBytes();
    updated = _replaceRunLengths(updated, 'StyleRun', oldLength: oldLength, newLength: text.length);
    updated = _replaceRunLengths(updated, 'ParagraphRun', oldLength: oldLength, newLength: text.length);
    return updated;
  }

  /// Finds and decodes the literal string assigned to the first `/Text` key.
  static ({int start, int end, Uint8List value})? _findTextString(Uint8List source) {
    int index = 0;
    while (index < source.length) {
      if (source[index] == 0x28) {
        index = _skipLiteralString(source, index);
        continue;
      }
      if (source[index] == 0x2f && _matchesName(source, index + 1, 'Text')) {
        index += 5;
        while (index < source.length && _isWhitespace(source[index])) {
          index++;
        }
        if (index < source.length && source[index] == 0x28) {
          final _PsdEngineParser parser = _PsdEngineParser(source, offset: index);
          final _PsdEngineString value = parser.readLiteralString();
          return (start: index + 1, end: parser.offset - 1, value: value.bytes);
        }
      }
      index++;
    }
    return null;
  }

  /// Adjusts one engine run-length array after the text length changes.
  static Uint8List _replaceRunLengths(Uint8List source, String section, {required int oldLength, required int newLength}) {
    if (oldLength == newLength) {
      return source;
    }
    final int sectionOffset = _findName(source, section);
    if (sectionOffset < 0) {
      return source;
    }
    final int lengthsOffset = _findName(source, 'RunLengthArray', start: sectionOffset + section.length + 1);
    if (lengthsOffset < 0) {
      return source;
    }
    int opening = lengthsOffset + 'RunLengthArray'.length + 1;
    while (opening < source.length && _isWhitespace(source[opening])) {
      opening++;
    }
    if (opening >= source.length || source[opening] != 0x5b) {
      return source;
    }
    final int closing = source.indexOf(0x5d, opening + 1);
    if (closing < 0) {
      return source;
    }
    final String contents = String.fromCharCodes(Uint8List.sublistView(source, opening + 1, closing));
    final List<int> lengths = RegExp(r'-?\d+').allMatches(contents).map((match) => int.parse(match.group(0)!)).toList();
    if (lengths.isEmpty) {
      return source;
    }
    final int target = newLength + 1;
    final List<int> adjusted = <int>[];
    int remaining = target;
    for (final int length in lengths) {
      if (remaining <= 0) {
        break;
      }
      final int kept = length.clamp(0, remaining);
      adjusted.add(kept);
      remaining -= kept;
    }
    if (adjusted.isEmpty) {
      adjusted.add(target);
    } else if (remaining > 0) {
      adjusted[adjusted.length - 1] += remaining;
    }
    final BytesBuilder output = BytesBuilder(copy: false)
      ..add(Uint8List.sublistView(source, 0, opening + 1))
      ..add(' ${adjusted.join(' ')} '.codeUnits)
      ..add(Uint8List.sublistView(source, closing));
    return output.takeBytes();
  }

  /// Reads font names from the engine resource dictionary.
  static List<String> _readFonts(_PsdEngineDictionary? resources) {
    final List<Object?>? fontSet = _list(resources?['FontSet']);
    if (fontSet == null) {
      return const <String>[];
    }
    return <String>[
      for (final Object? entry in fontSet)
        if (_decodeEngineString(_dictionary(entry)?['Name']) case final String name) _withoutTerminalNull(name),
    ];
  }

  /// Reads style runs and resolves their font indices through [fonts].
  static List<PsdTextStyleRun> _readStyleRuns(_PsdEngineDictionary? engine, List<String> fonts, int textLength) {
    final _PsdEngineDictionary? runs = _dictionary(engine?['StyleRun']);
    final List<Object?>? lengths = _list(runs?['RunLengthArray']);
    final List<Object?>? values = _list(runs?['RunArray']);
    if (lengths == null || values == null) {
      return const <PsdTextStyleRun>[];
    }
    final List<PsdTextStyleRun> result = <PsdTextStyleRun>[];
    int start = 0;
    for (int index = 0; index < lengths.length && index < values.length && start < textLength; index++) {
      final int storedLength = _integer(lengths[index]) ?? 0;
      final int length = storedLength.clamp(0, textLength - start);
      if (length == 0) {
        break;
      }
      final _PsdEngineDictionary? run = _dictionary(values[index]);
      final _PsdEngineDictionary? sheet = _dictionary(run?['StyleSheet']);
      final _PsdEngineDictionary? data = _dictionary(sheet?['StyleSheetData']);
      final int? fontIndex = _integer(data?['Font']);
      result.add(
        PsdTextStyleRun(
          start: start,
          length: length,
          style: PsdTextStyle(
            fontFamily: fontIndex != null && fontIndex >= 0 && fontIndex < fonts.length ? fonts[fontIndex] : null,
            fontSize: _number(data?['FontSize']),
            color: _readColor(data?['FillColor']),
            tracking: _number(data?['Tracking']),
            lineHeight: _boolean(data?['AutoLeading']) == true ? null : _number(data?['Leading']),
            fauxBold: _boolean(data?['FauxBold']) ?? false,
            fauxItalic: _boolean(data?['FauxItalic']) ?? false,
            underline: (_integer(data?['Underline']) ?? 0) != 0,
            strikethrough: (_integer(data?['Strikethrough']) ?? 0) != 0,
          ),
        ),
      );
      start += storedLength.clamp(0, textLength);
    }
    return result;
  }

  /// Reads paragraph ranges from the text engine.
  static List<PsdTextParagraph> _readParagraphs(_PsdEngineDictionary? engine, int textLength) {
    final _PsdEngineDictionary? runs = _dictionary(engine?['ParagraphRun']);
    final List<Object?>? lengths = _list(runs?['RunLengthArray']);
    final List<Object?>? values = _list(runs?['RunArray']);
    if (lengths == null || values == null) {
      return const <PsdTextParagraph>[];
    }
    final List<PsdTextParagraph> result = <PsdTextParagraph>[];
    int start = 0;
    for (int index = 0; index < lengths.length && index < values.length && start < textLength; index++) {
      final int storedLength = _integer(lengths[index]) ?? 0;
      final int length = storedLength.clamp(0, textLength - start);
      if (length == 0) {
        break;
      }
      final _PsdEngineDictionary? run = _dictionary(values[index]);
      final _PsdEngineDictionary? sheet = _dictionary(run?['ParagraphSheet']);
      final _PsdEngineDictionary? data = _dictionary(sheet?['Properties']) ?? _dictionary(sheet?['DefaultStyleSheet']);
      final int justification = _integer(data?['Justification']) ?? 0;
      result.add(
        PsdTextParagraph(
          start: start,
          length: length,
          justification: PsdTextJustification.values[justification.clamp(0, PsdTextJustification.values.length - 1)],
        ),
      );
      start += storedLength.clamp(0, textLength);
    }
    return result;
  }

  /// Converts an Adobe color dictionary into 8-bit RGBA components.
  static PsdTextColor? _readColor(Object? value) {
    final List<Object?>? components = _list(_dictionary(value)?['Values']);
    if (components == null || components.length < 4) {
      return null;
    }
    int channel(int index) => ((_number(components[index]) ?? 0).clamp(0, 1) * 255).round();
    return PsdTextColor(alpha: channel(0), red: channel(1), green: channel(2), blue: channel(3));
  }

  /// Encodes [text] using the byte order found in [original].
  static Uint8List _encodeEngineString(String text, Uint8List original) {
    final bool littleEndian = original.length >= 2 && original[0] == 0xff && original[1] == 0xfe;
    final BytesBuilder bytes = BytesBuilder(copy: false)..add(littleEndian ? const <int>[0xff, 0xfe] : const <int>[0xfe, 0xff]);
    for (final int unit in '$text\u0000'.codeUnits) {
      bytes.add(littleEndian ? <int>[unit & 0xff, unit >> 8] : <int>[unit >> 8, unit & 0xff]);
    }
    return bytes.takeBytes();
  }

  /// Escapes binary [value] for a PostScript literal string.
  static Uint8List _escapePostScript(Uint8List value) {
    final BytesBuilder bytes = BytesBuilder(copy: false);
    for (final int byte in value) {
      if (byte == 0x28 || byte == 0x29 || byte == 0x5c) {
        bytes.addByte(0x5c);
      }
      bytes.addByte(byte);
    }
    return bytes.takeBytes();
  }
}

/// A style and its normalized Photoshop run length.
final class _PsdNormalizedStyleRun {
  /// Run length including the terminal character when this is the last run.
  final int length;

  /// Style written for the run.
  final PsdTextStyle style;

  /// Creates a normalized style run.
  const _PsdNormalizedStyleRun(this.length, this.style);
}

/// A paragraph alignment and its normalized Photoshop run length.
final class _PsdNormalizedParagraph {
  /// Run length including the terminal character when this is the last run.
  final int length;

  /// Alignment written for the run.
  final PsdTextJustification justification;

  /// Creates a normalized paragraph run.
  const _PsdNormalizedParagraph(this.length, this.justification);
}

/// Binary writer for ASCII text-engine syntax and UTF-16 literal strings.
final class _PsdEngineWriter {
  /// Accumulated engine bytes.
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  /// Appends ASCII-compatible [value].
  void ascii(String value) => _bytes.add(value.codeUnits);

  /// Appends [value] as an escaped big-endian UTF-16 literal string.
  void unicodeString(String value, {bool terminalNull = false}) {
    final BytesBuilder encoded = BytesBuilder(copy: false)..add(const <int>[0xfe, 0xff]);
    final String stored = terminalNull ? '$value\u0000' : value;
    for (final int unit in stored.codeUnits) {
      encoded.add(<int>[unit >> 8, unit & 0xff]);
    }
    _bytes
      ..addByte(0x28)
      ..add(PsdTextEngine._escapePostScript(encoded.takeBytes()))
      ..addByte(0x29);
  }

  /// Returns all accumulated bytes.
  Uint8List takeBytes() => _bytes.takeBytes();
}

/// Creates the action descriptor surrounding semantic text-engine data.
PsdDescriptor _createTextDescriptor(PsdTextContent content, PsdTextBounds bounds) {
  final String text = content.text.replaceAll('\r\n', '\r').replaceAll('\n', '\r');
  return PsdDescriptor(
    name: '',
    classId: 'TxLr',
    items: <PsdDescriptorItem>[
      PsdDescriptorItem(key: 'Txt ', value: PsdStringValue('$text\u0000')),
      PsdDescriptorItem(
        key: 'textGridding',
        value: PsdEnumeratedValue(typeId: 'textGridding', value: 'None'),
      ),
      PsdDescriptorItem(
        key: 'Ornt',
        value: PsdEnumeratedValue(typeId: 'Ornt', value: content.orientation == PsdTextOrientation.vertical ? 'Vrtc' : 'Hrzn'),
      ),
      PsdDescriptorItem(
        key: 'AntA',
        value: PsdEnumeratedValue(typeId: 'Annt', value: 'AnSm'),
      ),
      PsdDescriptorItem(key: 'bounds', value: _createBoundsValue(bounds)),
      PsdDescriptorItem(key: 'boundingBox', value: _createBoundsValue(bounds)),
      PsdDescriptorItem(key: 'TextIndex', value: PsdIntegerValue(0)),
      PsdDescriptorItem(key: 'EngineData', value: PsdRawValue(PsdTextEngine.encode(content))),
    ],
  );
}

/// Creates the default no-warp descriptor for [orientation].
PsdDescriptor _createWarpDescriptor(PsdTextOrientation orientation) => PsdDescriptor(
  name: '',
  classId: 'warp',
  items: <PsdDescriptorItem>[
    PsdDescriptorItem(
      key: 'warpStyle',
      value: PsdEnumeratedValue(typeId: 'warpStyle', value: 'warpNone'),
    ),
    PsdDescriptorItem(key: 'warpValue', value: PsdDoubleValue(0)),
    PsdDescriptorItem(key: 'warpPerspective', value: PsdDoubleValue(0)),
    PsdDescriptorItem(key: 'warpPerspectiveOther', value: PsdDoubleValue(0)),
    PsdDescriptorItem(
      key: 'warpRotate',
      value: PsdEnumeratedValue(typeId: 'Ornt', value: orientation == PsdTextOrientation.vertical ? 'Vrtc' : 'Hrzn'),
    ),
  ],
);

/// Creates a Photoshop bounds descriptor from integer [bounds].
PsdObjectValue _createBoundsValue(PsdTextBounds bounds) => PsdObjectValue(
  PsdDescriptor(
    name: '',
    classId: 'bounds',
    items: <PsdDescriptorItem>[
      PsdDescriptorItem(
        key: 'Left',
        value: PsdUnitFloatValue(unit: '#Pxl', value: bounds.left.toDouble()),
      ),
      PsdDescriptorItem(
        key: 'Top ',
        value: PsdUnitFloatValue(unit: '#Pxl', value: bounds.top.toDouble()),
      ),
      PsdDescriptorItem(
        key: 'Rght',
        value: PsdUnitFloatValue(unit: '#Pxl', value: bounds.right.toDouble()),
      ),
      PsdDescriptorItem(
        key: 'Btom',
        value: PsdUnitFloatValue(unit: '#Pxl', value: bounds.bottom.toDouble()),
      ),
    ],
  ),
);

/// Normalizes sparse semantic [runs] into contiguous Photoshop style runs.
List<_PsdNormalizedStyleRun> _normalizeStyles(List<PsdTextStyleRun> runs, int textLength) {
  const PsdTextStyle fallback = PsdTextStyle(fontFamily: 'ArialMT', fontSize: 12, color: PsdTextColor(alpha: 255, red: 0, green: 0, blue: 0));
  if (runs.isEmpty || textLength == 0) {
    return <_PsdNormalizedStyleRun>[_PsdNormalizedStyleRun(textLength + 1, runs.isEmpty ? fallback : runs.first.style)];
  }
  final List<PsdTextStyleRun> sorted = List<PsdTextStyleRun>.of(runs)..sort((left, right) => left.start.compareTo(right.start));
  final List<_PsdNormalizedStyleRun> result = <_PsdNormalizedStyleRun>[];
  PsdTextStyle current = sorted.first.style;
  int offset = 0;
  for (final PsdTextStyleRun run in sorted) {
    final int start = run.start.clamp(offset, textLength);
    if (start > offset) {
      result.add(_PsdNormalizedStyleRun(start - offset, current));
    }
    final int end = (run.start + run.length).clamp(start, textLength);
    if (end > start) {
      result.add(_PsdNormalizedStyleRun(end - start, run.style));
    }
    current = run.style;
    offset = end;
  }
  if (offset < textLength) {
    result.add(_PsdNormalizedStyleRun(textLength - offset, current));
  }
  if (result.isEmpty) {
    result.add(_PsdNormalizedStyleRun(textLength, current));
  }
  final _PsdNormalizedStyleRun last = result.removeLast();
  result.add(_PsdNormalizedStyleRun(last.length + 1, last.style));
  return result;
}

/// Normalizes sparse semantic [paragraphs] into contiguous Photoshop runs.
List<_PsdNormalizedParagraph> _normalizeParagraphs(List<PsdTextParagraph> paragraphs, int textLength) {
  if (paragraphs.isEmpty || textLength == 0) {
    return <_PsdNormalizedParagraph>[_PsdNormalizedParagraph(textLength + 1, paragraphs.isEmpty ? PsdTextJustification.left : paragraphs.first.justification)];
  }
  final List<PsdTextParagraph> sorted = List<PsdTextParagraph>.of(paragraphs)..sort((left, right) => left.start.compareTo(right.start));
  final List<_PsdNormalizedParagraph> result = <_PsdNormalizedParagraph>[];
  PsdTextJustification current = sorted.first.justification;
  int offset = 0;
  for (final PsdTextParagraph paragraph in sorted) {
    final int start = paragraph.start.clamp(offset, textLength);
    if (start > offset) {
      result.add(_PsdNormalizedParagraph(start - offset, current));
    }
    final int end = (paragraph.start + paragraph.length).clamp(start, textLength);
    if (end > start) {
      result.add(_PsdNormalizedParagraph(end - start, paragraph.justification));
    }
    current = paragraph.justification;
    offset = end;
  }
  if (offset < textLength) {
    result.add(_PsdNormalizedParagraph(textLength - offset, current));
  }
  if (result.isEmpty) {
    result.add(_PsdNormalizedParagraph(textLength, current));
  }
  final _PsdNormalizedParagraph last = result.removeLast();
  result.add(_PsdNormalizedParagraph(last.length + 1, last.justification));
  return result;
}

/// Formats a finite text-engine number without unnecessary decimal zeros.
String _engineNumber(double value) {
  if (!value.isFinite) {
    return '0';
  }
  return value == value.roundToDouble() ? value.toInt().toString() : value.toString();
}

/// Converts one 8-bit channel into Adobe's zero-to-one color range.
String _engineColor(int value) => _engineNumber(value.clamp(0, 255) / 255);

/// Removes the Photoshop terminator from a descriptor or engine string.
String _withoutTerminalNull(String value) => value.endsWith('\u0000') ? value.substring(0, value.length - 1) : value;

/// A dictionary parsed from Adobe text-engine data.
final class _PsdEngineDictionary {
  /// Ordered values indexed by PostScript name.
  final Map<String, Object?> values;

  /// Creates an engine dictionary.
  const _PsdEngineDictionary(this.values);

  /// Returns the value associated with [key].
  Object? operator [](String key) => values[key];
}

/// A byte string parsed from Adobe text-engine data.
final class _PsdEngineString {
  /// Unescaped string bytes.
  final Uint8List bytes;

  /// Creates a binary engine string.
  const _PsdEngineString(this.bytes);
}

/// A PostScript name used as a dictionary value.
final class _PsdEngineName {
  /// Name without its leading slash.
  final String value;

  /// Creates an engine name.
  const _PsdEngineName(this.value);
}

/// Bounded parser for the PostScript subset used by Adobe `EngineData`.
final class _PsdEngineParser {
  /// Bytes being parsed.
  final Uint8List _bytes;

  /// Current byte offset.
  int _offset;

  /// Creates an engine-data parser.
  _PsdEngineParser(this._bytes, {this._offset = 0});

  /// Current byte offset.
  int get offset => _offset;

  /// Parses the single root value.
  Object? parse() {
    _skipTrivia();
    final Object? result = _readValue();
    _skipTrivia();
    return result;
  }

  /// Reads a literal string at the current offset.
  _PsdEngineString readLiteralString() {
    if (_offset >= _bytes.length || _bytes[_offset] != 0x28) {
      throw const FormatException('Expected EngineData string');
    }
    _offset++;
    int depth = 1;
    final BytesBuilder value = BytesBuilder(copy: false);
    while (_offset < _bytes.length) {
      final int byte = _bytes[_offset++];
      if (byte == 0x5c) {
        if (_offset >= _bytes.length) {
          throw const FormatException('Truncated EngineData escape');
        }
        final int escaped = _bytes[_offset++];
        if (escaped == 0x0a) {
          continue;
        }
        if (escaped == 0x0d) {
          if (_offset < _bytes.length && _bytes[_offset] == 0x0a) {
            _offset++;
          }
          continue;
        }
        if (escaped >= 0x30 && escaped <= 0x37) {
          int octal = escaped - 0x30;
          int count = 1;
          while (count < 3 && _offset < _bytes.length && _bytes[_offset] >= 0x30 && _bytes[_offset] <= 0x37) {
            octal = octal * 8 + _bytes[_offset++] - 0x30;
            count++;
          }
          value.addByte(octal & 0xff);
        } else {
          value.addByte(switch (escaped) {
            0x6e => 0x0a,
            0x72 => 0x0d,
            0x74 => 0x09,
            0x62 => 0x08,
            0x66 => 0x0c,
            _ => escaped,
          });
        }
      } else if (byte == 0x28) {
        depth++;
        value.addByte(byte);
      } else if (byte == 0x29) {
        if (--depth == 0) {
          return _PsdEngineString(value.takeBytes());
        }
        value.addByte(byte);
      } else {
        value.addByte(byte);
      }
    }
    throw const FormatException('Unterminated EngineData string');
  }

  /// Reads one engine-data value.
  Object? _readValue() {
    _skipTrivia();
    if (_offset >= _bytes.length) {
      throw const FormatException('Missing EngineData value');
    }
    if (_startsWith('<<')) {
      return _readDictionary();
    }
    if (_bytes[_offset] == 0x5b) {
      return _readArray();
    }
    if (_bytes[_offset] == 0x28) {
      return readLiteralString();
    }
    if (_bytes[_offset] == 0x2f) {
      return _PsdEngineName(_readName());
    }
    final String token = _readToken();
    if (token == 'true') {
      return true;
    }
    if (token == 'false') {
      return false;
    }
    if (token == 'null') {
      return null;
    }
    return num.tryParse(token) ?? token;
  }

  /// Reads a `<< ... >>` dictionary.
  _PsdEngineDictionary _readDictionary() {
    _offset += 2;
    final Map<String, Object?> values = <String, Object?>{};
    while (true) {
      _skipTrivia();
      if (_startsWith('>>')) {
        _offset += 2;
        return _PsdEngineDictionary(values);
      }
      if (_offset >= _bytes.length || _bytes[_offset] != 0x2f) {
        throw const FormatException('Expected EngineData dictionary key');
      }
      final String key = _readName();
      values[key] = _readValue();
    }
  }

  /// Reads a `[ ... ]` array.
  List<Object?> _readArray() {
    _offset++;
    final List<Object?> values = <Object?>[];
    while (true) {
      _skipTrivia();
      if (_offset >= _bytes.length) {
        throw const FormatException('Unterminated EngineData array');
      }
      if (_bytes[_offset] == 0x5d) {
        _offset++;
        return values;
      }
      values.add(_readValue());
    }
  }

  /// Reads a slash-prefixed PostScript name.
  String _readName() {
    _offset++;
    final int start = _offset;
    while (_offset < _bytes.length && !_isDelimiter(_bytes[_offset])) {
      _offset++;
    }
    return String.fromCharCodes(Uint8List.sublistView(_bytes, start, _offset));
  }

  /// Reads a bare token.
  String _readToken() {
    final int start = _offset;
    while (_offset < _bytes.length && !_isDelimiter(_bytes[_offset])) {
      _offset++;
    }
    if (start == _offset) {
      throw const FormatException('Empty EngineData token');
    }
    return String.fromCharCodes(Uint8List.sublistView(_bytes, start, _offset));
  }

  /// Skips spaces and percent comments.
  void _skipTrivia() {
    while (_offset < _bytes.length) {
      if (_isWhitespace(_bytes[_offset])) {
        _offset++;
      } else if (_bytes[_offset] == 0x25) {
        while (_offset < _bytes.length && _bytes[_offset] != 0x0a && _bytes[_offset] != 0x0d) {
          _offset++;
        }
      } else {
        return;
      }
    }
  }

  /// Whether upcoming bytes equal [value].
  bool _startsWith(String value) {
    if (_offset + value.length > _bytes.length) {
      return false;
    }
    for (int index = 0; index < value.length; index++) {
      if (_bytes[_offset + index] != value.codeUnitAt(index)) {
        return false;
      }
    }
    return true;
  }
}

/// Casts [value] to an engine dictionary when possible.
_PsdEngineDictionary? _dictionary(Object? value) => value is _PsdEngineDictionary ? value : null;

/// Casts [value] to an engine list when possible.
List<Object?>? _list(Object? value) => value is List<Object?> ? value : null;

/// Converts an engine numeric value to a double.
double? _number(Object? value) => value is num ? value.toDouble() : null;

/// Converts an engine numeric value to an integer.
int? _integer(Object? value) => value is num ? value.toInt() : null;

/// Casts an engine value to a Boolean.
bool? _boolean(Object? value) => value is bool ? value : null;

/// Decodes a binary Adobe engine string, including its byte-order mark.
String? _decodeEngineString(Object? value) {
  if (value is! _PsdEngineString) {
    return null;
  }
  final Uint8List bytes = value.bytes;
  if (bytes.length >= 2 && ((bytes[0] == 0xfe && bytes[1] == 0xff) || (bytes[0] == 0xff && bytes[1] == 0xfe))) {
    final bool littleEndian = bytes[0] == 0xff;
    final List<int> units = <int>[];
    for (int index = 2; index + 1 < bytes.length; index += 2) {
      units.add(littleEndian ? bytes[index] | bytes[index + 1] << 8 : bytes[index] << 8 | bytes[index + 1]);
    }
    return String.fromCharCodes(units);
  }
  return String.fromCharCodes(bytes);
}

/// Whether [source] contains [name] followed by a name delimiter.
bool _matchesName(Uint8List source, int start, String name) {
  if (start + name.length > source.length) {
    return false;
  }
  for (int index = 0; index < name.length; index++) {
    if (source[start + index] != name.codeUnitAt(index)) {
      return false;
    }
  }
  final int end = start + name.length;
  return end == source.length || _isDelimiter(source[end]);
}

/// Finds a slash-prefixed [name] outside literal strings.
int _findName(Uint8List source, String name, {int start = 0}) {
  int index = start;
  while (index < source.length) {
    if (source[index] == 0x28) {
      index = _skipLiteralString(source, index);
    } else if (source[index] == 0x2f && _matchesName(source, index + 1, name)) {
      return index;
    } else {
      index++;
    }
  }
  return -1;
}

/// Skips a complete PostScript literal string starting at [offset].
int _skipLiteralString(Uint8List source, int offset) {
  try {
    final _PsdEngineParser parser = _PsdEngineParser(source, offset: offset);
    parser.readLiteralString();
    return parser.offset;
  } on FormatException {
    return source.length;
  }
}

/// Whether [byte] is PostScript whitespace.
bool _isWhitespace(int byte) => byte == 0 || byte == 9 || byte == 10 || byte == 12 || byte == 13 || byte == 32;

/// Whether [byte] ends a PostScript name or bare token.
bool _isDelimiter(int byte) =>
    _isWhitespace(byte) || byte == 0x28 || byte == 0x29 || byte == 0x3c || byte == 0x3e || byte == 0x5b || byte == 0x5d || byte == 0x7b || byte == 0x7d || byte == 0x2f || byte == 0x25;
