part of '../text.dart';

/// Encodes semantic [content] as self-contained Adobe text-engine data.
Uint8List _encodeTextEngine(PsdTextContent content) {
  final String text = content.text.replaceAll('\r\n', '\r').replaceAll('\n', '\r');
  final List<_PsdTextRun<PsdTextStyle>> styles = _normalizeStyles(content.styleRuns, text.length);
  final List<_PsdTextRun<PsdTextParagraph>> paragraphs = _normalizeParagraphs(content.paragraphs, text.length);
  final List<PsdTextFont> fonts = <PsdTextFont>[
    const PsdTextFont(name: 'AdobeInvisFont'),
  ];
  for (final _PsdTextRun<PsdTextStyle> run in styles) {
    final PsdTextFont font = run.value.font ?? PsdTextFont(name: run.value.fontFamily ?? 'MyriadPro-Regular');
    if (!fonts.any((candidate) => candidate.name == font.name)) {
      fonts.add(font);
    }
  }
  final PsdTextStyle normalStyle = styles.first.value;
  final PsdTextParagraph normalParagraph = paragraphs.first.value;
  final _PsdEngineWriter writer = _PsdEngineWriter()
    ..ascii('<< /EngineDict << /Editor << /Text ')
    ..unicodeString('$text\r')
    ..ascii(
      ' >> /ParagraphRun << /DefaultRunData << /ParagraphSheet << '
      '/DefaultStyleSheet 0 /Properties << >> >> '
      '/Adjustments << /Axis [ 1 0 1 ] /XY [ 0 0 ] >> >> /RunArray [ ',
    );
  for (final _PsdTextRun<PsdTextParagraph> paragraph in paragraphs) {
    writer.ascii('<< /ParagraphSheet << /DefaultStyleSheet 0 /Properties << ');
    _writeParagraphProperties(writer, paragraph.value);
    writer.ascii('>> >> /Adjustments << /Axis [ ');
    _writeNumbers(writer, paragraph.value.adjustments.axis);
    writer.ascii('] /XY [ ');
    _writeNumbers(writer, paragraph.value.adjustments.xy);
    writer.ascii('] >> >> ');
  }
  writer.ascii(
    '] /RunLengthArray [ ${paragraphs.map((run) => run.length).join(' ')} ] /IsJoinable 1 >> '
    '/StyleRun << /DefaultRunData << /StyleSheet << /StyleSheetData << >> >> >> /RunArray [ ',
  );
  for (final _PsdTextRun<PsdTextStyle> run in styles) {
    writer.ascii('<< /StyleSheet << /StyleSheetData << ');
    _writeStyleProperties(writer, run.value, fonts);
    writer.ascii('>> >> >> ');
  }
  writer.ascii(
    '] /RunLengthArray [ ${styles.map((run) => run.length).join(' ')} ] /IsJoinable 2 >> '
    '/GridInfo << /GridIsOn ${content.gridInfo.isOn} /ShowGrid ${content.gridInfo.show} '
    '/GridSize ${_engineNumber(content.gridInfo.size)} /GridLeading ${_engineNumber(content.gridInfo.leading)} '
    '/GridColor ',
  );
  _writeColor(writer, content.gridInfo.color);
  writer.ascii('/GridLeadingFillColor ');
  _writeColor(writer, content.gridInfo.leadingFillColor);
  writer.ascii(
    '/AlignLineHeightToGridFlags ${content.gridInfo.alignLineHeightToGrid} >> '
    '/AntiAlias ${_encodeEngineAntiAlias(content.antiAlias)} '
    '/UseFractionalGlyphWidths ${content.useFractionalGlyphWidths} '
    '/Rendered << /Version 1 /Shapes << '
    '/WritingDirection ${content.orientation == PsdTextOrientation.vertical ? 2 : 0} /Children [ '
    '<< /ShapeType ${content.shapeType == PsdTextShapeType.box ? 1 : 0} '
    '/Procession ${content.orientation == PsdTextOrientation.vertical ? 1 : 0} '
    '/Lines << /WritingDirection ${content.orientation == PsdTextOrientation.vertical ? 2 : 0} /Children [ ] >> '
    '/Cookie << /Photoshop << /ShapeType ${content.shapeType == PsdTextShapeType.box ? 1 : 0} ',
  );
  if (content.shapeType == PsdTextShapeType.box) {
    writer.ascii(
      '/BoxBounds [ ${_engineNumber(content.boxBounds.left)} ${_engineNumber(content.boxBounds.top)} '
      '${_engineNumber(content.boxBounds.right)} ${_engineNumber(content.boxBounds.bottom)} ] ',
    );
  } else {
    writer.ascii('/PointBase [ ${_engineNumber(content.pointBase.x)} ${_engineNumber(content.pointBase.y)} ] ');
  }
  writer.ascii(
    '/Base << /ShapeType ${content.shapeType == PsdTextShapeType.box ? 1 : 0} '
    '/TransformPoint0 [ 1 0 ] /TransformPoint1 [ 0 1 ] /TransformPoint2 [ 0 0 ] >> '
    '>> >> >> ] >> >> >> ',
  );
  writer.ascii('/ResourceDict << ');
  _writeResources(writer, content, normalStyle, normalParagraph, fonts);
  writer.ascii('>> /DocumentResources << ');
  _writeResources(writer, content, normalStyle, normalParagraph, fonts);
  writer.ascii('>> >>');
  return writer.takeBytes();
}

/// Writes every supported character-style property.
void _writeStyleProperties(
  _PsdEngineWriter writer,
  PsdTextStyle style,
  List<PsdTextFont> fonts,
) {
  final String fontName = style.resolvedFontFamily ?? 'MyriadPro-Regular';
  final int fontIndex = fonts.indexWhere((font) => font.name == fontName);
  writer.ascii(
    '/Font ${fontIndex < 0 ? 0 : fontIndex} '
    '/FontSize ${_engineNumber(style.fontSize ?? 12)} '
    '/FauxBold ${style.fauxBold} /FauxItalic ${style.fauxItalic} '
    '/AutoLeading ${style.automaticLeading} /Leading ${_engineNumber(style.lineHeight ?? 0)} '
    '/HorizontalScale ${_engineNumber(style.horizontalScale)} '
    '/VerticalScale ${_engineNumber(style.verticalScale)} '
    '/Tracking ${_engineNumber(style.tracking ?? 0)} '
    '/AutoKerning ${style.automaticKerning} /Kerning ${_engineNumber(style.kerning)} '
    '/BaselineShift ${_engineNumber(style.baselineShift)} '
    '/FontCaps ${style.fontCaps} /FontBaseline ${style.fontBaseline} '
    '/Underline ${style.underline} /Strikethrough ${style.strikethrough} '
    '/Ligatures ${style.ligatures} /DLigatures ${style.discretionaryLigatures} '
    '/BaselineDirection ${style.baselineDirection} /Tsume ${_engineNumber(style.tsume)} '
    '/StyleRunAlignment ${style.styleRunAlignment} /Language ${style.language} '
    '/NoBreak ${style.noBreak} /FillColor ',
  );
  _writeColor(
    writer,
    style.color ?? const PsdTextColor(alpha: 255, red: 0, green: 0, blue: 0),
  );
  writer.ascii('/StrokeColor ');
  _writeColor(
    writer,
    style.strokeColor ?? const PsdTextColor(alpha: 255, red: 0, green: 0, blue: 0),
  );
  writer.ascii(
    '/FillFlag ${style.fillEnabled} /StrokeFlag ${style.strokeEnabled} '
    '/FillFirst ${style.fillFirst} /YUnderline ${_engineNumber(style.underlinePosition)} '
    '/OutlineWidth ${_engineNumber(style.outlineWidth)} '
    '/CharacterDirection ${style.characterDirection} /HindiNumbers ${style.hindiNumbers} '
    '/Kashida ${style.kashida} /DiacriticPos ${style.diacriticPosition} ',
  );
}

/// Writes every supported paragraph-style property.
void _writeParagraphProperties(
  _PsdEngineWriter writer,
  PsdTextParagraph paragraph,
) {
  writer.ascii(
    '/Justification ${_encodeJustification(paragraph.justification)} '
    '/FirstLineIndent ${_engineNumber(paragraph.firstLineIndent)} '
    '/StartIndent ${_engineNumber(paragraph.startIndent)} '
    '/EndIndent ${_engineNumber(paragraph.endIndent)} '
    '/SpaceBefore ${_engineNumber(paragraph.spaceBefore)} '
    '/SpaceAfter ${_engineNumber(paragraph.spaceAfter)} '
    '/AutoHyphenate ${paragraph.automaticHyphenation} '
    '/HyphenatedWordSize ${paragraph.hyphenatedWordSize} '
    '/PreHyphen ${paragraph.preHyphen} /PostHyphen ${paragraph.postHyphen} '
    '/ConsecutiveHyphens ${paragraph.consecutiveHyphens} '
    '/Zone ${_engineNumber(paragraph.zone)} /WordSpacing [ ',
  );
  _writeSpacing(writer, paragraph.wordSpacing);
  writer.ascii('] /LetterSpacing [ ');
  _writeSpacing(writer, paragraph.letterSpacing);
  writer.ascii('] /GlyphSpacing [ ');
  _writeSpacing(writer, paragraph.glyphSpacing);
  writer.ascii(
    '] /AutoLeading ${_engineNumber(paragraph.automaticLeading)} '
    '/LeadingType ${paragraph.leadingType} /Hanging ${paragraph.hanging} '
    '/Burasagari ${paragraph.burasagari} /KinsokuOrder ${paragraph.kinsokuOrder} '
    '/EveryLineComposer ${paragraph.everyLineComposer} ',
  );
}

/// Writes a minimum, desired, and maximum spacing triplet.
void _writeSpacing(_PsdEngineWriter writer, PsdTextSpacing spacing) {
  writer.ascii(
    '${_engineNumber(spacing.minimum)} ${_engineNumber(spacing.desired)} ${_engineNumber(spacing.maximum)} ',
  );
}

/// Writes a numeric EngineData array body.
void _writeNumbers(_PsdEngineWriter writer, List<double> values) {
  for (final double value in values) {
    writer.ascii('${_engineNumber(value)} ');
  }
}

/// Writes a color dictionary without converting its original color space.
void _writeColor(_PsdEngineWriter writer, PsdTextColor color) {
  if (color.values case final List<double> values) {
    writer.ascii('<< /Type ${color.colorSpace.engineType} /Values [ ${values.map(_engineNumber).join(' ')} ] >> ');
    return;
  }
  switch (color.colorSpace) {
    case PsdTextColorSpace.grayscale:
      writer.ascii(
        '<< /Type 0 /Values [ ${_engineColor(color.alpha)} ${_engineColor(color.gray ?? color.red)} ] >> ',
      );
    case PsdTextColorSpace.rgb:
      writer.ascii(
        '<< /Type 1 /Values [ ${_engineColor(color.alpha)} ${_engineColor(color.red)} '
        '${_engineColor(color.green)} ${_engineColor(color.blue)} ] >> ',
      );
    case PsdTextColorSpace.cmyk:
      writer.ascii(
        '<< /Type 2 /Values [ ${_engineColor(color.alpha)} ${_engineColor(color.cyan ?? 0)} '
        '${_engineColor(color.magenta ?? 0)} ${_engineColor(color.yellow ?? 0)} '
        '${_engineColor(color.black ?? 0)} ] >> ',
      );
  }
}

/// Writes resources needed to reopen generated text as editable Photoshop text.
void _writeResources(
  _PsdEngineWriter writer,
  PsdTextContent content,
  PsdTextStyle normalStyle,
  PsdTextParagraph normalParagraph,
  List<PsdTextFont> fonts,
) {
  writer.ascii('/KinsokuSet [ << /Name ');
  writer.unicodeString('PhotoshopKinsokuHard');
  writer.ascii(' /NoStart ');
  writer.unicodeString('、。，．・：；？！ー―’”）〕］｝〉》」』】ヽヾゝゞ々ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶ゛゜?!)]},.:;℃℉¢％‰');
  writer.ascii(' /NoEnd ');
  writer.unicodeString('‘“（〔［｛〈《「『【([{￥＄£＠§〒＃');
  writer.ascii(' /Keep ');
  writer.unicodeString('―‥');
  writer.ascii(' /Hanging ');
  writer.unicodeString('、。.,');
  writer.ascii(' >> << /Name ');
  writer.unicodeString('PhotoshopKinsokuSoft');
  writer.ascii(' /NoStart ');
  writer.unicodeString('、。，．・：；？！’”）〕］｝〉》」』】ヽヾゝゞ々');
  writer.ascii(' /NoEnd ');
  writer.unicodeString('‘“（〔［｛〈《「『【');
  writer.ascii(' /Keep ');
  writer.unicodeString('―‥');
  writer.ascii(' /Hanging ');
  writer.unicodeString('、。.,');
  writer.ascii(' >> ] /MojiKumiSet [ ');
  for (int index = 1; index <= 4; index++) {
    writer.ascii('<< /InternalName ');
    writer.unicodeString('Photoshop6MojiKumiSet$index');
    writer.ascii(' >> ');
  }
  writer.ascii(
    '] /TheNormalStyleSheet 0 /TheNormalParagraphSheet 0 '
    '/ParagraphSheetSet [ << /Name ',
  );
  writer.unicodeString('Normal RGB');
  writer.ascii(' /DefaultStyleSheet 0 /Properties << ');
  _writeParagraphProperties(writer, normalParagraph);
  writer.ascii('>> >> ] /StyleSheetSet [ << /Name ');
  writer.unicodeString('Normal RGB');
  writer.ascii(' /StyleSheetData << ');
  _writeStyleProperties(writer, normalStyle, fonts);
  writer.ascii('>> >> ] /FontSet [ ');
  for (final PsdTextFont font in fonts) {
    writer.ascii('<< /Name ');
    writer.unicodeString(font.name);
    writer.ascii(
      ' /Script ${font.script} /FontType ${font.fontType} /Synthetic ${font.synthetic} >> ',
    );
  }
  writer.ascii(
    '] /SuperscriptSize ${_engineNumber(content.superscriptSize)} '
    '/SuperscriptPosition ${_engineNumber(content.superscriptPosition)} '
    '/SubscriptSize ${_engineNumber(content.subscriptSize)} '
    '/SubscriptPosition ${_engineNumber(content.subscriptPosition)} '
    '/SmallCapSize ${_engineNumber(content.smallCapSize)} ',
  );
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
      ..add(_escapePostScript(encoded.takeBytes()))
      ..addByte(0x29);
  }

  /// Returns all accumulated bytes.
  Uint8List takeBytes() => _bytes.takeBytes();
}

/// Converts a semantic paragraph alignment to Adobe's text-engine value.
int _encodeJustification(PsdTextJustification justification) => switch (justification) {
  PsdTextJustification.left => 0,
  PsdTextJustification.right => 1,
  PsdTextJustification.center => 2,
  PsdTextJustification.justifyLeft => 3,
  PsdTextJustification.justifyRight => 4,
  PsdTextJustification.justifyCenter => 5,
  PsdTextJustification.justifyAll => 6,
};

/// Encodes an antialiasing mode for Adobe text-engine data.
int _encodeEngineAntiAlias(PsdTextAntiAlias antiAlias) => switch (antiAlias) {
  PsdTextAntiAlias.none => 0,
  PsdTextAntiAlias.crisp => 1,
  PsdTextAntiAlias.strong => 2,
  PsdTextAntiAlias.smooth => 3,
  PsdTextAntiAlias.sharp || PsdTextAntiAlias.platform || PsdTextAntiAlias.platformLcd => 4,
};

/// Formats a finite text-engine number without unnecessary decimal zeros.
String _engineNumber(double value) {
  if (!value.isFinite) {
    return '0';
  }
  return value == value.roundToDouble() ? value.toInt().toString() : value.toString();
}

/// Converts one 8-bit channel into Adobe's zero-to-one color range.
String _engineColor(int value) => _engineNumber(value.clamp(0, 255) / 255);
