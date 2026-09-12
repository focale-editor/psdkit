import 'dart:typed_data';

import 'package:pscore/pscore.dart';

/// Maximum dictionary and array nesting accepted from untrusted engine data.
///
/// Photoshop writes far shallower structures; the bound keeps a hostile file
/// from exhausting the stack through the parser's recursion.
const int _maximumEngineDepth = 64;

/// Direction in which Photoshop lays out a text layer.
enum PsdTextOrientation {
  /// Text advances horizontally.
  horizontal,

  /// Text advances vertically.
  vertical,
}

/// Antialiasing mode requested for editable Photoshop text.
enum PsdTextAntiAlias {
  /// Disables glyph antialiasing.
  none,

  /// Prioritizes sharp glyph edges.
  sharp,

  /// Prioritizes crisp glyph edges.
  crisp,

  /// Uses stronger antialiasing.
  strong,

  /// Uses smoother antialiasing.
  smooth,

  /// Uses the platform grayscale text renderer.
  platform,

  /// Uses the platform LCD text renderer.
  platformLcd,
}

/// Pixel-grid behavior stored by a Photoshop text descriptor.
enum PsdTextGridding {
  /// Leaves text coordinates unrounded.
  none,

  /// Rounds text coordinates to the pixel grid.
  round,
}

/// Geometry used by the Photoshop text engine.
enum PsdTextShapeType {
  /// Text starts at a point and grows without a fixed box.
  point,

  /// Text flows inside a rectangular paragraph box.
  box,
}

/// Color space retained from an Adobe text-engine color value.
enum PsdTextColorSpace {
  /// A single grayscale component.
  grayscale,

  /// Red, green, and blue components.
  rgb,

  /// Cyan, magenta, yellow, and black components.
  cmyk,
}

/// Warp preset stored by a Photoshop type tool.
enum PsdTextWarpStyle {
  /// No text warp.
  none,

  /// Arc warp.
  arc,

  /// Lower arc warp.
  arcLower,

  /// Upper arc warp.
  arcUpper,

  /// Arch warp.
  arch,

  /// Bulge warp.
  bulge,

  /// Lower shell warp.
  shellLower,

  /// Upper shell warp.
  shellUpper,

  /// Flag warp.
  flag,

  /// Wave warp.
  wave,

  /// Fish warp.
  fish,

  /// Rising warp.
  rise,

  /// Fisheye warp.
  fisheye,

  /// Inflate warp.
  inflate,

  /// Squeeze warp.
  squeeze,

  /// Twist warp.
  twist,

  /// Cylinder warp.
  cylinder,

  /// Custom warp whose extra descriptor properties remain in the raw descriptor.
  custom,
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

/// Converts Adobe's text-engine paragraph value to a semantic alignment.
PsdTextJustification _decodeJustification(int value) => switch (value) {
  0 => PsdTextJustification.left,
  1 => PsdTextJustification.right,
  2 => PsdTextJustification.center,
  3 => PsdTextJustification.justifyLeft,
  4 => PsdTextJustification.justifyRight,
  5 => PsdTextJustification.justifyCenter,
  6 => PsdTextJustification.justifyAll,
  _ => PsdTextJustification.left,
};

/// Font metadata referenced by a Photoshop text style.
final class PsdTextFont {
  /// PostScript or Photoshop font name.
  final String name;

  /// Adobe script identifier.
  final int script;

  /// Adobe font-type identifier.
  final int fontType;

  /// Adobe synthetic-font flags.
  final int synthetic;

  /// Creates a text-engine font reference.
  const PsdTextFont({
    required this.name,
    this.script = 0,
    this.fontType = 0,
    this.synthetic = 0,
  });
}

/// A text color retaining its original grayscale, RGB, or CMYK space.
final class PsdTextColor {
  /// Original Adobe color space.
  final PsdTextColorSpace colorSpace;

  /// Alpha component from 0 through 255.
  final int alpha;

  /// Red component from 0 through 255.
  final int red;

  /// Green component from 0 through 255.
  final int green;

  /// Blue component from 0 through 255.
  final int blue;

  /// Original grayscale component, when [colorSpace] is grayscale.
  final int? gray;

  /// Original cyan component, when [colorSpace] is CMYK.
  final int? cyan;

  /// Original magenta component, when [colorSpace] is CMYK.
  final int? magenta;

  /// Original yellow component, when [colorSpace] is CMYK.
  final int? yellow;

  /// Original black component, when [colorSpace] is CMYK.
  final int? black;

  /// Creates an RGB text color.
  const PsdTextColor({
    required this.alpha,
    required this.red,
    required this.green,
    required this.blue,
  }) : colorSpace = PsdTextColorSpace.rgb,
       gray = null,
       cyan = null,
       magenta = null,
       yellow = null,
       black = null;

  /// Creates a grayscale text color.
  const PsdTextColor.grayscale({this.alpha = 255, required int value})
    : colorSpace = PsdTextColorSpace.grayscale,
      red = value,
      green = value,
      blue = value,
      gray = value,
      cyan = null,
      magenta = null,
      yellow = null,
      black = null;

  /// Creates a CMYK text color while exposing an approximate RGB preview.
  factory PsdTextColor.cmyk({
    int alpha = 255,
    required int cyan,
    required int magenta,
    required int yellow,
    required int black,
  }) {
    final int normalizedCyan = cyan.clamp(0, 255);
    final int normalizedMagenta = magenta.clamp(0, 255);
    final int normalizedYellow = yellow.clamp(0, 255);
    final int normalizedBlack = black.clamp(0, 255);
    return PsdTextColor._(
      colorSpace: PsdTextColorSpace.cmyk,
      alpha: alpha,
      red: ((255 - normalizedCyan) * (255 - normalizedBlack) / 255).round(),
      green: ((255 - normalizedMagenta) * (255 - normalizedBlack) / 255).round(),
      blue: ((255 - normalizedYellow) * (255 - normalizedBlack) / 255).round(),
      cyan: normalizedCyan,
      magenta: normalizedMagenta,
      yellow: normalizedYellow,
      black: normalizedBlack,
    );
  }

  /// Creates a color with already resolved preview and source components.
  const PsdTextColor._({
    required this.colorSpace,
    required this.alpha,
    required this.red,
    required this.green,
    required this.blue,
    this.cyan,
    this.magenta,
    this.yellow,
    this.black,
  }) : gray = null;

  /// The color packed as an ARGB integer.
  int get argb => alpha << 24 | red << 16 | green << 8 | blue;
}

/// Three values used for minimum, desired, and maximum text spacing.
final class PsdTextSpacing {
  /// Minimum permitted factor.
  final double minimum;

  /// Preferred factor.
  final double desired;

  /// Maximum permitted factor.
  final double maximum;

  /// Creates a text-spacing triplet.
  const PsdTextSpacing({
    required this.minimum,
    required this.desired,
    required this.maximum,
  });
}

/// Paragraph adjustments applied by the Adobe text engine.
final class PsdTextParagraphAdjustments {
  /// Axis adjustment values.
  final List<double> axis;

  /// Horizontal and vertical adjustment values.
  final List<double> xy;

  /// Creates paragraph adjustments.
  const PsdTextParagraphAdjustments({
    this.axis = const <double>[1, 0, 1],
    this.xy = const <double>[0, 0],
  });
}

/// Formatting applied to a range of Photoshop text.
final class PsdTextStyle {
  /// PostScript or Photoshop font name, when known.
  final String? fontFamily;

  /// Complete font metadata, when available.
  final PsdTextFont? font;

  /// Font size in text points, when explicitly stored.
  final double? fontSize;

  /// Foreground color, when explicitly stored.
  final PsdTextColor? color;

  /// Additional tracking in thousandths of an em.
  final double? tracking;

  /// Explicit line height, or `null` for automatic leading.
  final double? lineHeight;

  /// Whether Photoshop calculates leading automatically.
  final bool automaticLeading;

  /// Horizontal glyph scale where 1 is 100 percent.
  final double horizontalScale;

  /// Vertical glyph scale where 1 is 100 percent.
  final double verticalScale;

  /// Whether Photoshop calculates kerning automatically.
  final bool automaticKerning;

  /// Explicit kerning value.
  final double kerning;

  /// Vertical baseline offset in text points.
  final double baselineShift;

  /// Adobe capitalization mode identifier.
  final int fontCaps;

  /// Adobe baseline mode identifier.
  final int fontBaseline;

  /// Whether Photoshop synthesizes a bold face.
  final bool fauxBold;

  /// Whether Photoshop synthesizes an italic face.
  final bool fauxItalic;

  /// Whether the range is underlined.
  final bool underline;

  /// Whether the range is struck through.
  final bool strikethrough;

  /// Whether standard ligatures are enabled.
  final bool ligatures;

  /// Whether discretionary ligatures are enabled.
  final bool discretionaryLigatures;

  /// Adobe baseline-direction identifier.
  final int baselineDirection;

  /// Japanese glyph compression amount.
  final double tsume;

  /// Adobe style-run alignment identifier.
  final int styleRunAlignment;

  /// Adobe language identifier.
  final int language;

  /// Whether line breaks are prohibited in the range.
  final bool noBreak;

  /// Stroke color, when explicitly stored.
  final PsdTextColor? strokeColor;

  /// Whether the fill is painted.
  final bool fillEnabled;

  /// Whether the stroke is painted.
  final bool strokeEnabled;

  /// Whether the fill is painted before the stroke.
  final bool fillFirst;

  /// Adobe underline-position value.
  final double underlinePosition;

  /// Text outline width.
  final double outlineWidth;

  /// Adobe character-direction identifier.
  final int characterDirection;

  /// Whether Hindi numerals are used.
  final bool hindiNumbers;

  /// Adobe kashida width identifier.
  final int kashida;

  /// Adobe diacritic-position identifier.
  final int diacriticPosition;

  /// Creates a text style.
  const PsdTextStyle({
    this.fontFamily,
    this.font,
    this.fontSize,
    this.color,
    this.tracking,
    this.lineHeight,
    bool? automaticLeading,
    this.horizontalScale = 1,
    this.verticalScale = 1,
    this.automaticKerning = true,
    this.kerning = 0,
    this.baselineShift = 0,
    this.fontCaps = 0,
    this.fontBaseline = 0,
    this.fauxBold = false,
    this.fauxItalic = false,
    this.underline = false,
    this.strikethrough = false,
    this.ligatures = true,
    this.discretionaryLigatures = false,
    this.baselineDirection = 2,
    this.tsume = 0,
    this.styleRunAlignment = 2,
    this.language = 0,
    this.noBreak = false,
    this.strokeColor,
    this.fillEnabled = true,
    this.strokeEnabled = false,
    this.fillFirst = true,
    this.underlinePosition = 1,
    this.outlineWidth = 1,
    this.characterDirection = 0,
    this.hindiNumbers = false,
    this.kashida = 1,
    this.diacriticPosition = 2,
  }) : automaticLeading = automaticLeading ?? lineHeight == null;

  /// Preferred font name from complete metadata or the compatibility field.
  String? get resolvedFontFamily => font?.name ?? fontFamily;
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

  /// Indentation applied to the first line.
  final double firstLineIndent;

  /// Indentation at the leading edge.
  final double startIndent;

  /// Indentation at the trailing edge.
  final double endIndent;

  /// Space inserted before the paragraph.
  final double spaceBefore;

  /// Space inserted after the paragraph.
  final double spaceAfter;

  /// Whether automatic hyphenation is enabled.
  final bool automaticHyphenation;

  /// Minimum word length eligible for hyphenation.
  final int hyphenatedWordSize;

  /// Minimum characters retained before a hyphen.
  final int preHyphen;

  /// Minimum characters retained after a hyphen.
  final int postHyphen;

  /// Maximum consecutive hyphenated lines.
  final int consecutiveHyphens;

  /// Hyphenation zone width.
  final double zone;

  /// Word-spacing constraints.
  final PsdTextSpacing wordSpacing;

  /// Letter-spacing constraints.
  final PsdTextSpacing letterSpacing;

  /// Glyph-scaling constraints.
  final PsdTextSpacing glyphSpacing;

  /// Automatic-leading ratio.
  final double automaticLeading;

  /// Adobe leading-type identifier.
  final int leadingType;

  /// Whether punctuation may hang outside the text edge.
  final bool hanging;

  /// Whether Japanese burasagari punctuation is enabled.
  final bool burasagari;

  /// Adobe kinsoku-order identifier.
  final int kinsokuOrder;

  /// Whether the every-line composer is enabled.
  final bool everyLineComposer;

  /// Low-level paragraph adjustments.
  final PsdTextParagraphAdjustments adjustments;

  /// Creates a paragraph range.
  const PsdTextParagraph({
    required this.start,
    required this.length,
    required this.justification,
    this.firstLineIndent = 0,
    this.startIndent = 0,
    this.endIndent = 0,
    this.spaceBefore = 0,
    this.spaceAfter = 0,
    this.automaticHyphenation = true,
    this.hyphenatedWordSize = 6,
    this.preHyphen = 2,
    this.postHyphen = 2,
    this.consecutiveHyphens = 8,
    this.zone = 36,
    this.wordSpacing = const PsdTextSpacing(minimum: 0.8, desired: 1, maximum: 1.33),
    this.letterSpacing = const PsdTextSpacing(minimum: 0, desired: 0, maximum: 0),
    this.glyphSpacing = const PsdTextSpacing(minimum: 1, desired: 1, maximum: 1),
    this.automaticLeading = 1.2,
    this.leadingType = 0,
    this.hanging = false,
    this.burasagari = false,
    this.kinsokuOrder = 0,
    this.everyLineComposer = false,
    this.adjustments = const PsdTextParagraphAdjustments(),
  });
}

/// A two-dimensional point used by text-engine shape metadata.
final class PsdTextPoint {
  /// Horizontal coordinate.
  final double x;

  /// Vertical coordinate.
  final double y;

  /// Origin point.
  static const PsdTextPoint zero = PsdTextPoint(x: 0, y: 0);

  /// Creates a text-engine point.
  const PsdTextPoint({required this.x, required this.y});
}

/// Rectangle used by text-engine box geometry.
final class PsdTextBox {
  /// Left edge.
  final double left;

  /// Top edge.
  final double top;

  /// Right edge.
  final double right;

  /// Bottom edge.
  final double bottom;

  /// Empty box.
  static const PsdTextBox zero = PsdTextBox(left: 0, top: 0, right: 0, bottom: 0);

  /// Creates a text-engine box.
  const PsdTextBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });
}

/// Baseline-grid settings stored in Adobe text-engine data.
final class PsdTextGridInfo {
  /// Whether the grid affects text layout.
  final bool isOn;

  /// Whether Photoshop displays the grid.
  final bool show;

  /// Grid cell size.
  final double size;

  /// Grid leading.
  final double leading;

  /// Grid line color.
  final PsdTextColor color;

  /// Grid leading-fill color.
  final PsdTextColor leadingFillColor;

  /// Whether line height is aligned to the grid.
  final bool alignLineHeightToGrid;

  /// Creates baseline-grid settings.
  const PsdTextGridInfo({
    this.isOn = false,
    this.show = false,
    this.size = 18,
    this.leading = 22,
    this.color = const PsdTextColor(alpha: 0, red: 0, green: 0, blue: 255),
    this.leadingFillColor = const PsdTextColor(alpha: 0, red: 0, green: 0, blue: 255),
    this.alignLineHeightToGrid = false,
  });
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

  /// Text-engine antialiasing mode.
  final PsdTextAntiAlias antiAlias;

  /// Pixel-grid behavior from the surrounding type-tool descriptor.
  final PsdTextGridding gridding;

  /// Whether fractional glyph advances are retained.
  final bool useFractionalGlyphWidths;

  /// Baseline-grid settings.
  final PsdTextGridInfo gridInfo;

  /// Point-text or paragraph-box geometry.
  final PsdTextShapeType shapeType;

  /// Anchor used by point text.
  final PsdTextPoint pointBase;

  /// Flow rectangle used by box text.
  final PsdTextBox boxBounds;

  /// Relative superscript glyph size.
  final double superscriptSize;

  /// Relative superscript baseline position.
  final double superscriptPosition;

  /// Relative subscript glyph size.
  final double subscriptSize;

  /// Relative subscript baseline position.
  final double subscriptPosition;

  /// Relative small-cap glyph size.
  final double smallCapSize;

  /// Creates semantic text-layer contents.
  const PsdTextContent({
    required this.text,
    required this.orientation,
    this.styleRuns = const <PsdTextStyleRun>[],
    this.paragraphs = const <PsdTextParagraph>[],
    this.antiAlias = PsdTextAntiAlias.sharp,
    this.gridding = PsdTextGridding.none,
    this.useFractionalGlyphWidths = true,
    this.gridInfo = const PsdTextGridInfo(),
    this.shapeType = PsdTextShapeType.point,
    this.pointBase = PsdTextPoint.zero,
    this.boxBounds = PsdTextBox.zero,
    this.superscriptSize = 0.583,
    this.superscriptPosition = 0.333,
    this.subscriptSize = 0.583,
    this.subscriptPosition = 0.333,
    this.smallCapSize = 0.7,
  });

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

/// Four single-precision bounds stored at the end of a `TySh` block.
final class PsdTextBounds {
  /// Left edge.
  final double left;

  /// Top edge.
  final double top;

  /// Right edge.
  final double right;

  /// Bottom edge.
  final double bottom;

  /// Empty bounds used by point text without a text box.
  static const PsdTextBounds zero = PsdTextBounds(left: 0, top: 0, right: 0, bottom: 0);

  /// Creates type-tool bounds.
  const PsdTextBounds({required this.left, required this.top, required this.right, required this.bottom});
}

/// A numeric type-tool descriptor value carrying a Photoshop unit.
final class PsdTextUnitValue {
  /// Four-character Photoshop unit, such as `#Pxl` or `#Pnt`.
  final String unit;

  /// Numeric value expressed in [unit].
  final double value;

  /// Creates a unit-bearing text value.
  const PsdTextUnitValue({required this.unit, required this.value});
}

/// Bounds stored inside the type-tool action descriptor.
final class PsdTextDescriptorBounds {
  /// Left edge and its unit.
  final PsdTextUnitValue left;

  /// Top edge and its unit.
  final PsdTextUnitValue top;

  /// Right edge and its unit.
  final PsdTextUnitValue right;

  /// Bottom edge and its unit.
  final PsdTextUnitValue bottom;

  /// Creates descriptor bounds with independent units for every edge.
  const PsdTextDescriptorBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// Creates pixel-based descriptor bounds.
  factory PsdTextDescriptorBounds.pixels({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) => PsdTextDescriptorBounds(
    left: PsdTextUnitValue(unit: '#Pxl', value: left),
    top: PsdTextUnitValue(unit: '#Pxl', value: top),
    right: PsdTextUnitValue(unit: '#Pxl', value: right),
    bottom: PsdTextUnitValue(unit: '#Pxl', value: bottom),
  );
}

/// Common editable properties of a Photoshop text-warp descriptor.
final class PsdTextWarp {
  /// Selected Photoshop warp preset.
  final PsdTextWarpStyle style;

  /// Warp bend amount.
  final double value;

  /// Horizontal perspective amount.
  final double perspective;

  /// Vertical perspective amount.
  final double perspectiveOther;

  /// Direction in which the warp is applied.
  final PsdTextOrientation rotation;

  /// Default no-warp settings.
  static const PsdTextWarp none = PsdTextWarp(
    style: PsdTextWarpStyle.none,
    value: 0,
    perspective: 0,
    perspectiveOther: 0,
    rotation: PsdTextOrientation.horizontal,
  );

  /// Creates text-warp settings.
  const PsdTextWarp({
    required this.style,
    required this.value,
    required this.perspective,
    required this.perspectiveOther,
    required this.rotation,
  });
}

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

/// A slash-prefixed PostScript name found in decoded Adobe text-engine data.
final class PsdTextEngineName {
  /// Name without its leading slash.
  final String value;

  /// Creates a decoded text-engine name.
  const PsdTextEngineName({required this.value});
}

/// Document-level Photoshop `Txt2` text-engine data.
final class PsdGlobalTextEngineData {
  /// Original text-engine bytes.
  final Uint8List data;

  /// Creates document-level text-engine data.
  PsdGlobalTextEngineData({required Uint8List data}) : data = Uint8List.fromList(data);

  /// Decodes the PostScript-like payload into maps, lists, values, and names.
  Object? get structure => PsdTextEngine.decodeStructure(data);

  /// Decodes [structure], returning `null` when the payload is malformed.
  Object? get tryStructure {
    try {
      return structure;
    } on FormatException {
      return null;
    }
  }
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
  final PsDescriptor textDescriptor;

  /// Warp record version, normally 1.
  final int warpVersion;

  /// Action-descriptor version for [warpDescriptor], normally 16.
  final int warpDescriptorVersion;

  /// Descriptor containing text warp settings.
  final PsDescriptor warpDescriptor;

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
    PsdTextDescriptorBounds? descriptorBounds,
    PsdTextDescriptorBounds? boundingBox,
    PsdTextWarp? warp,
    int textIndex = 0,
  }) => PsdTypeTool(
    transform: transform,
    bounds: bounds,
    textDescriptor: _createTextDescriptor(
      content,
      descriptorBounds: descriptorBounds,
      boundingBox: boundingBox,
      textIndex: textIndex,
    ),
    warpDescriptor: _createWarpDescriptor(
      warp ??
          PsdTextWarp(
            style: PsdTextWarpStyle.none,
            value: 0,
            perspective: 0,
            perspectiveOther: 0,
            rotation: content.orientation,
          ),
    ),
  );

  /// Plain Unicode text stored under the `Txt ` descriptor key.
  String get text => switch (textDescriptor.value('Txt ')) {
    PsStringValue(:final String value) => _withoutTerminalNull(value),
    _ => '',
  };

  /// Layout direction stored by the type-tool descriptor.
  PsdTextOrientation get orientation => switch (textDescriptor.value('Ornt')) {
    PsEnumeratedValue(:final String value) when value == 'Vrtc' => PsdTextOrientation.vertical,
    _ => PsdTextOrientation.horizontal,
  };

  /// Pixel-grid behavior stored by the type-tool descriptor.
  PsdTextGridding get gridding => switch (textDescriptor.value('textGridding')) {
    PsEnumeratedValue(:final String value) when value == 'Rnd ' => PsdTextGridding.round,
    _ => PsdTextGridding.none,
  };

  /// Antialiasing mode stored by the type-tool descriptor.
  PsdTextAntiAlias get antiAlias => _decodeDescriptorAntiAlias(textDescriptor.value('AntA'));

  /// Optional layout bounds from the text descriptor.
  PsdTextDescriptorBounds? get descriptorBounds => _readDescriptorBounds(textDescriptor.value('bounds'));

  /// Optional rendered bounding box from the text descriptor.
  PsdTextDescriptorBounds? get boundingBox => _readDescriptorBounds(textDescriptor.value('boundingBox'));

  /// Photoshop text object index.
  int get textIndex => switch (textDescriptor.value('TextIndex')) {
    PsIntegerValue(:final int value) => value,
    _ => 0,
  };

  /// Common warp properties decoded from [warpDescriptor].
  PsdTextWarp get warp => _readWarp(warpDescriptor, fallbackRotation: orientation);

  /// Semantic text, styles, and paragraphs suitable for application models.
  PsdTextContent get content => PsdTextEngine.decode(
    engineData,
    fallbackText: text,
    orientation: orientation,
    fallbackAntiAlias: antiAlias,
    antiAliasOverride: antiAlias,
    gridding: gridding,
  );

  /// Raw Adobe text-engine program stored under `EngineData`.
  Uint8List? get engineData => switch (textDescriptor.value('EngineData')) {
    PsRawValue(:final Uint8List value) => value,
    _ => null,
  };

  /// Returns a copy containing [text] in both descriptor text fields.
  PsdTypeTool withText(String text) {
    final String normalized = text.replaceAll('\r\n', '\r').replaceAll('\n', '\r');
    PsDescriptor descriptor = textDescriptor.withValue('Txt ', PsStringValue(value: '$normalized\u0000'));
    final Uint8List? engine = engineData;
    if (engine != null) {
      descriptor = descriptor.withValue('EngineData', PsRawValue(value: PsdTextEngine.replaceText(engine, normalized)));
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
    final PsDescriptor descriptor = textDescriptor
        .withValue('Txt ', PsStringValue(value: '${content.text.replaceAll('\r\n', '\r').replaceAll('\n', '\r')}\u0000'))
        .withValue(
          'textGridding',
          PsEnumeratedValue(
            typeId: 'textGridding',
            value: content.gridding == PsdTextGridding.round ? 'Rnd ' : 'None',
          ),
        )
        .withValue(
          'Ornt',
          PsEnumeratedValue(typeId: 'Ornt', value: content.orientation == PsdTextOrientation.vertical ? 'Vrtc' : 'Hrzn'),
        )
        .withValue(
          'AntA',
          PsEnumeratedValue(typeId: 'Annt', value: _encodeDescriptorAntiAlias(content.antiAlias)),
        )
        .withValue('EngineData', PsRawValue(value: PsdTextEngine.encode(content)));
    final PsDescriptor warp = warpDescriptor.withValue(
      'warpRotate',
      PsEnumeratedValue(typeId: 'Ornt', value: content.orientation == PsdTextOrientation.vertical ? 'Vrtc' : 'Hrzn'),
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

  /// Returns a copy with common warp properties updated.
  ///
  /// Unknown custom-warp descriptor keys are retained.
  PsdTypeTool withWarp(PsdTextWarp warp) => PsdTypeTool(
    version: version,
    transform: transform,
    textVersion: textVersion,
    textDescriptorVersion: textDescriptorVersion,
    textDescriptor: textDescriptor,
    warpVersion: warpVersion,
    warpDescriptorVersion: warpDescriptorVersion,
    warpDescriptor: _updateWarpDescriptor(warpDescriptor, warp),
    bounds: bounds,
    trailingData: trailingData,
  );
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
    final int textVersion = reader.readUint16();
    final int textDescriptorVersion = reader.readUint32();
    late final ({PsDescriptor descriptor, int bytesRead}) text;
    try {
      text = PsDescriptorCodec.decodePrefix(Uint8List.sublistView(reader.bytes, reader.offset));
    } on FormatException catch (error) {
      throw FormatException('Invalid TySh text descriptor: $error');
    }
    reader.skip(text.bytesRead);
    final int warpVersion = reader.readUint16();
    final int warpDescriptorVersion = reader.readUint32();
    late final ({PsDescriptor descriptor, int bytesRead}) warp;
    try {
      warp = PsDescriptorCodec.decodePrefix(Uint8List.sublistView(reader.bytes, reader.offset));
    } on FormatException catch (error) {
      throw FormatException('Invalid TySh warp descriptor: $error');
    }
    reader.skip(warp.bytesRead);
    final PsdTextBounds bounds = PsdTextBounds(
      left: reader.readFloat32(),
      top: reader.readFloat32(),
      right: reader.readFloat32(),
      bottom: reader.readFloat32(),
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
    final PsBinaryWriter writer = PsBinaryWriter()
      ..writeUint16(typeTool.version)
      ..writeFloat64(typeTool.transform.xx)
      ..writeFloat64(typeTool.transform.xy)
      ..writeFloat64(typeTool.transform.yx)
      ..writeFloat64(typeTool.transform.yy)
      ..writeFloat64(typeTool.transform.tx)
      ..writeFloat64(typeTool.transform.ty)
      ..writeUint16(typeTool.textVersion)
      ..writeUint32(typeTool.textDescriptorVersion)
      ..writeBytes(PsDescriptorCodec.encode(typeTool.textDescriptor))
      ..writeUint16(typeTool.warpVersion)
      ..writeUint32(typeTool.warpDescriptorVersion)
      ..writeBytes(PsDescriptorCodec.encode(typeTool.warpDescriptor))
      ..writeFloat32(typeTool.bounds.left)
      ..writeFloat32(typeTool.bounds.top)
      ..writeFloat32(typeTool.bounds.right)
      ..writeFloat32(typeTool.bounds.bottom)
      ..writeBytes(typeTool.trailingData);
    return writer.takeBytes();
  }
}

/// Parses and updates Adobe text-engine data without normalizing unknown keys.
abstract final class PsdTextEngine {
  /// Decodes arbitrary Adobe text-engine data into immutable Dart values.
  ///
  /// Dictionaries become maps, arrays become lists, binary text strings become
  /// Dart strings, and slash-prefixed values become [PsdTextEngineName] objects.
  static Object? decodeStructure(Uint8List engineData) => _publicEngineValue(
    _PsdEngineParser(bytes: engineData).parse(),
  );

  /// Extracts semantic text information from opaque Adobe [engineData].
  static PsdTextContent decode(
    Uint8List? engineData, {
    required String fallbackText,
    required PsdTextOrientation orientation,
    PsdTextAntiAlias fallbackAntiAlias = PsdTextAntiAlias.sharp,
    PsdTextAntiAlias? antiAliasOverride,
    PsdTextGridding gridding = PsdTextGridding.none,
  }) {
    if (engineData == null) {
      return PsdTextContent(
        text: fallbackText,
        orientation: orientation,
        antiAlias: fallbackAntiAlias,
        gridding: gridding,
      );
    }
    try {
      final Object? rootValue = _PsdEngineParser(bytes: engineData).parse();
      final _PsdEngineDictionary? root = _dictionary(rootValue);
      final _PsdEngineDictionary? engine = _dictionary(root?['EngineDict']);
      final _PsdEngineDictionary? resources = _dictionary(root?['ResourceDict']);
      final _PsdEngineDictionary? editor = _dictionary(engine?['Editor']);
      final String text = _decodeEngineString(editor?['Text']) ?? fallbackText;
      final String logicalText = _withoutEngineTerminator(text);
      final List<PsdTextFont> fonts = _readFonts(resources);
      final _PsdTextShapeData shape = _readShape(engine);
      return PsdTextContent(
        text: logicalText,
        orientation: orientation,
        styleRuns: _readStyleRuns(engine, resources, fonts, logicalText.length),
        paragraphs: _readParagraphs(engine, resources, logicalText.length),
        antiAlias:
            antiAliasOverride ??
            _decodeEngineAntiAlias(
              _integer(engine?['AntiAlias']),
              fallback: fallbackAntiAlias,
            ),
        gridding: gridding,
        useFractionalGlyphWidths: _engineBoolean(engine?['UseFractionalGlyphWidths']) ?? true,
        gridInfo: _readGridInfo(engine),
        shapeType: shape.type,
        pointBase: shape.point,
        boxBounds: shape.box,
        superscriptSize: _number(resources?['SuperscriptSize']) ?? 0.583,
        superscriptPosition: _number(resources?['SuperscriptPosition']) ?? 0.333,
        subscriptSize: _number(resources?['SubscriptSize']) ?? 0.583,
        subscriptPosition: _number(resources?['SubscriptPosition']) ?? 0.333,
        smallCapSize: _number(resources?['SmallCapSize']) ?? 0.7,
      );
    } on FormatException {
      return PsdTextContent(
        text: fallbackText,
        orientation: orientation,
        antiAlias: fallbackAntiAlias,
        gridding: gridding,
      );
    }
  }

  /// Encodes semantic [content] as self-contained Adobe text-engine data.
  static Uint8List encode(PsdTextContent content) {
    final String text = content.text.replaceAll('\r\n', '\r').replaceAll('\n', '\r');
    final List<_PsdNormalizedStyleRun> styles = _normalizeStyles(content.styleRuns, text.length);
    final List<_PsdNormalizedParagraph> paragraphs = _normalizeParagraphs(content.paragraphs, text.length);
    final List<PsdTextFont> fonts = <PsdTextFont>[
      const PsdTextFont(name: 'AdobeInvisFont'),
    ];
    for (final _PsdNormalizedStyleRun run in styles) {
      final PsdTextFont font = run.style.font ?? PsdTextFont(name: run.style.fontFamily ?? 'MyriadPro-Regular');
      if (!fonts.any((candidate) => candidate.name == font.name)) {
        fonts.add(font);
      }
    }
    final PsdTextStyle normalStyle = styles.first.style;
    final PsdTextParagraph normalParagraph = paragraphs.first.paragraph;
    final _PsdEngineWriter writer = _PsdEngineWriter()
      ..ascii('<< /EngineDict << /Editor << /Text ')
      ..unicodeString('$text\r')
      ..ascii(
        ' >> /ParagraphRun << /DefaultRunData << /ParagraphSheet << '
        '/DefaultStyleSheet 0 /Properties << >> >> '
        '/Adjustments << /Axis [ 1 0 1 ] /XY [ 0 0 ] >> >> /RunArray [ ',
      );
    for (final _PsdNormalizedParagraph paragraph in paragraphs) {
      writer.ascii('<< /ParagraphSheet << /DefaultStyleSheet 0 /Properties << ');
      _writeParagraphProperties(writer, paragraph.paragraph);
      writer.ascii('>> >> /Adjustments << /Axis [ ');
      _writeNumbers(writer, paragraph.paragraph.adjustments.axis);
      writer.ascii('] /XY [ ');
      _writeNumbers(writer, paragraph.paragraph.adjustments.xy);
      writer.ascii('] >> >> ');
    }
    writer.ascii(
      '] /RunLengthArray [ ${paragraphs.map((run) => run.length).join(' ')} ] /IsJoinable 1 >> '
      '/StyleRun << /DefaultRunData << /StyleSheet << /StyleSheetData << >> >> >> /RunArray [ ',
    );
    for (final _PsdNormalizedStyleRun run in styles) {
      writer.ascii('<< /StyleSheet << /StyleSheetData << ');
      _writeStyleProperties(writer, run.style, fonts);
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

  /// Replaces the PostScript string assigned to `/Text` in [engineData].
  static Uint8List replaceText(Uint8List engineData, String text) {
    final ({int start, int end, Uint8List value})? target = _findTextString(engineData);
    if (target == null) {
      return engineData;
    }
    final int oldLength = _withoutEngineTerminator(_decodeEngineString(_PsdEngineString(bytes: target.value)) ?? '').length;
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
          final _PsdEngineParser parser = _PsdEngineParser(bytes: source, offset: index);
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

  /// Reads font metadata from the engine resource dictionary.
  static List<PsdTextFont> _readFonts(_PsdEngineDictionary? resources) {
    final List<Object?>? fontSet = _list(resources?['FontSet']);
    if (fontSet == null) {
      return const <PsdTextFont>[];
    }
    final List<PsdTextFont> fonts = <PsdTextFont>[];
    for (final Object? entry in fontSet) {
      final _PsdEngineDictionary? font = _dictionary(entry);
      final String? name = _decodeEngineString(font?['Name']);
      if (name == null) {
        continue;
      }
      fonts.add(
        PsdTextFont(
          name: _withoutTerminalNull(name),
          script: _integer(font?['Script']) ?? 0,
          fontType: _integer(font?['FontType']) ?? 0,
          synthetic: _integer(font?['Synthetic']) ?? 0,
        ),
      );
    }
    return fonts;
  }

  /// Reads style runs and resolves inherited sheets and font references.
  static List<PsdTextStyleRun> _readStyleRuns(
    _PsdEngineDictionary? engine,
    _PsdEngineDictionary? resources,
    List<PsdTextFont> fonts,
    int textLength,
  ) {
    final _PsdEngineDictionary? runs = _dictionary(engine?['StyleRun']);
    final List<Object?>? lengths = _list(runs?['RunLengthArray']);
    final List<Object?>? values = _list(runs?['RunArray']);
    if (lengths == null || values == null) {
      return const <PsdTextStyleRun>[];
    }
    final int normalIndex = _integer(resources?['TheNormalStyleSheet']) ?? 0;
    final _PsdEngineDictionary? normalData = _resourceStyleData(resources, normalIndex);
    final _PsdEngineDictionary? defaultData = _styleData(_dictionary(runs?['DefaultRunData']));
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
      final int sheetIndex = _integer(sheet?['DefaultStyleSheet']) ?? normalIndex;
      final _PsdEngineDictionary data = _mergeDictionaries(<_PsdEngineDictionary?>[
        normalData,
        defaultData,
        _resourceStyleData(resources, sheetIndex),
        _dictionary(sheet?['StyleSheetData']),
      ]);
      final int? fontIndex = _integer(data['Font']);
      final PsdTextFont? font = fontIndex != null && fontIndex >= 0 && fontIndex < fonts.length ? fonts[fontIndex] : null;
      final bool automaticLeading = _engineBoolean(data['AutoLeading']) ?? _number(data['Leading']) == null;
      result.add(
        PsdTextStyleRun(
          start: start,
          length: length,
          style: PsdTextStyle(
            fontFamily: font?.name,
            font: font,
            fontSize: _number(data['FontSize']),
            color: _readColor(data['FillColor']),
            tracking: _number(data['Tracking']),
            lineHeight: automaticLeading ? null : _number(data['Leading']),
            automaticLeading: automaticLeading,
            horizontalScale: _number(data['HorizontalScale']) ?? 1,
            verticalScale: _number(data['VerticalScale']) ?? 1,
            automaticKerning: _engineBoolean(data['AutoKerning']) ?? true,
            kerning: _number(data['Kerning']) ?? 0,
            baselineShift: _number(data['BaselineShift']) ?? 0,
            fontCaps: _integer(data['FontCaps']) ?? 0,
            fontBaseline: _integer(data['FontBaseline']) ?? 0,
            fauxBold: _engineBoolean(data['FauxBold']) ?? false,
            fauxItalic: _engineBoolean(data['FauxItalic']) ?? false,
            underline: _engineBoolean(data['Underline']) ?? false,
            strikethrough: _engineBoolean(data['Strikethrough']) ?? false,
            ligatures: _engineBoolean(data['Ligatures']) ?? true,
            discretionaryLigatures: _engineBoolean(data['DLigatures']) ?? false,
            baselineDirection: _integer(data['BaselineDirection']) ?? 2,
            tsume: _number(data['Tsume']) ?? 0,
            styleRunAlignment: _integer(data['StyleRunAlignment']) ?? 2,
            language: _integer(data['Language']) ?? 0,
            noBreak: _engineBoolean(data['NoBreak']) ?? false,
            strokeColor: _readColor(data['StrokeColor']),
            fillEnabled: _engineBoolean(data['FillFlag']) ?? true,
            strokeEnabled: _engineBoolean(data['StrokeFlag']) ?? false,
            fillFirst: _engineBoolean(data['FillFirst']) ?? true,
            underlinePosition: _number(data['YUnderline']) ?? 1,
            outlineWidth: _number(data['OutlineWidth']) ?? 1,
            characterDirection: _integer(data['CharacterDirection']) ?? 0,
            hindiNumbers: _engineBoolean(data['HindiNumbers']) ?? false,
            kashida: _integer(data['Kashida']) ?? 1,
            diacriticPosition: _integer(data['DiacriticPos']) ?? 2,
          ),
        ),
      );
      start += length;
    }
    return result;
  }

  /// Reads paragraph ranges from the text engine.
  static List<PsdTextParagraph> _readParagraphs(
    _PsdEngineDictionary? engine,
    _PsdEngineDictionary? resources,
    int textLength,
  ) {
    final _PsdEngineDictionary? runs = _dictionary(engine?['ParagraphRun']);
    final List<Object?>? lengths = _list(runs?['RunLengthArray']);
    final List<Object?>? values = _list(runs?['RunArray']);
    if (lengths == null || values == null) {
      return const <PsdTextParagraph>[];
    }
    final int normalIndex = _integer(resources?['TheNormalParagraphSheet']) ?? 0;
    final _PsdEngineDictionary? normalData = _resourceParagraphData(resources, normalIndex);
    final _PsdEngineDictionary? defaultRun = _dictionary(runs?['DefaultRunData']);
    final _PsdEngineDictionary? defaultSheet = _dictionary(defaultRun?['ParagraphSheet']);
    final _PsdEngineDictionary? defaultData = _dictionary(defaultSheet?['Properties']);
    final _PsdEngineDictionary? defaultAdjustments = _dictionary(defaultRun?['Adjustments']);
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
      final int sheetIndex = _integer(sheet?['DefaultStyleSheet']) ?? normalIndex;
      final _PsdEngineDictionary data = _mergeDictionaries(<_PsdEngineDictionary?>[
        normalData,
        defaultData,
        _resourceParagraphData(resources, sheetIndex),
        _dictionary(sheet?['Properties']),
      ]);
      final _PsdEngineDictionary adjustments = _mergeDictionaries(<_PsdEngineDictionary?>[
        defaultAdjustments,
        _dictionary(run?['Adjustments']),
      ]);
      final int justification = _integer(data['Justification']) ?? 0;
      result.add(
        PsdTextParagraph(
          start: start,
          length: length,
          justification: _decodeJustification(justification),
          firstLineIndent: _number(data['FirstLineIndent']) ?? 0,
          startIndent: _number(data['StartIndent']) ?? 0,
          endIndent: _number(data['EndIndent']) ?? 0,
          spaceBefore: _number(data['SpaceBefore']) ?? 0,
          spaceAfter: _number(data['SpaceAfter']) ?? 0,
          automaticHyphenation: _engineBoolean(data['AutoHyphenate']) ?? true,
          hyphenatedWordSize: _integer(data['HyphenatedWordSize']) ?? 6,
          preHyphen: _integer(data['PreHyphen']) ?? 2,
          postHyphen: _integer(data['PostHyphen']) ?? 2,
          consecutiveHyphens: _integer(data['ConsecutiveHyphens']) ?? 8,
          zone: _number(data['Zone']) ?? 36,
          wordSpacing: _readSpacing(data['WordSpacing'], fallback: const PsdTextSpacing(minimum: 0.8, desired: 1, maximum: 1.33)),
          letterSpacing: _readSpacing(data['LetterSpacing'], fallback: const PsdTextSpacing(minimum: 0, desired: 0, maximum: 0)),
          glyphSpacing: _readSpacing(data['GlyphSpacing'], fallback: const PsdTextSpacing(minimum: 1, desired: 1, maximum: 1)),
          automaticLeading: _number(data['AutoLeading']) ?? 1.2,
          leadingType: _integer(data['LeadingType']) ?? 0,
          hanging: _engineBoolean(data['Hanging']) ?? false,
          burasagari: _engineBoolean(data['Burasagari']) ?? false,
          kinsokuOrder: _integer(data['KinsokuOrder']) ?? 0,
          everyLineComposer: _engineBoolean(data['EveryLineComposer']) ?? false,
          adjustments: PsdTextParagraphAdjustments(
            axis: _numbers(adjustments['Axis']) ?? const <double>[1, 0, 1],
            xy: _numbers(adjustments['XY']) ?? const <double>[0, 0],
          ),
        ),
      );
      start += length;
    }
    return result;
  }

  /// Converts an Adobe color dictionary into 8-bit RGBA components.
  static PsdTextColor? _readColor(Object? value) {
    final _PsdEngineDictionary? color = _dictionary(value);
    final int? type = _integer(color?['Type']);
    final List<Object?>? components = _list(color?['Values']);
    if (type == null || components == null) {
      return null;
    }

    /// Converts one normalized color component to an 8-bit channel.
    int channel(int index) => ((_number(components[index]) ?? 0).clamp(0, 1) * 255).round();
    return switch (type) {
      0 when components.length >= 2 => PsdTextColor.grayscale(alpha: channel(0), value: channel(1)),
      1 when components.length >= 4 => PsdTextColor(alpha: channel(0), red: channel(1), green: channel(2), blue: channel(3)),
      2 when components.length >= 5 => PsdTextColor.cmyk(
        alpha: channel(0),
        cyan: channel(1),
        magenta: channel(2),
        yellow: channel(3),
        black: channel(4),
      ),
      _ => null,
    };
  }

  /// Reads baseline-grid properties from [engine].
  static PsdTextGridInfo _readGridInfo(_PsdEngineDictionary? engine) {
    final _PsdEngineDictionary? grid = _dictionary(engine?['GridInfo']);
    return PsdTextGridInfo(
      isOn: _engineBoolean(grid?['GridIsOn']) ?? false,
      show: _engineBoolean(grid?['ShowGrid']) ?? false,
      size: _number(grid?['GridSize']) ?? 18,
      leading: _number(grid?['GridLeading']) ?? 22,
      color: _readColor(grid?['GridColor']) ?? const PsdTextColor(alpha: 0, red: 0, green: 0, blue: 255),
      leadingFillColor: _readColor(grid?['GridLeadingFillColor']) ?? _readColor(grid?['GridColor']) ?? const PsdTextColor(alpha: 0, red: 0, green: 0, blue: 255),
      alignLineHeightToGrid: _engineBoolean(grid?['AlignLineHeightToGridFlags']) ?? false,
    );
  }

  /// Reads point or box geometry from the rendered text-engine tree.
  static _PsdTextShapeData _readShape(_PsdEngineDictionary? engine) {
    final _PsdEngineDictionary? rendered = _dictionary(engine?['Rendered']);
    final _PsdEngineDictionary? shapes = _dictionary(rendered?['Shapes']);
    final List<Object?>? children = _list(shapes?['Children']);
    final _PsdEngineDictionary? child = children == null || children.isEmpty ? null : _dictionary(children.first);
    final _PsdEngineDictionary? cookie = _dictionary(child?['Cookie']) ?? _dictionary(child?['Cookies']);
    final _PsdEngineDictionary? photoshop = _dictionary(cookie?['Photoshop']);
    final List<double>? point = _numbers(photoshop?['PointBase']);
    final List<double>? box = _numbers(photoshop?['BoxBounds']);
    final PsdTextShapeType type = _integer(photoshop?['ShapeType']) == 1 ? PsdTextShapeType.box : PsdTextShapeType.point;
    return _PsdTextShapeData(
      type: type,
      point: point != null && point.length >= 2 ? PsdTextPoint(x: point[0], y: point[1]) : PsdTextPoint.zero,
      box: box != null && box.length >= 4 ? PsdTextBox(left: box[0], top: box[1], right: box[2], bottom: box[3]) : PsdTextBox.zero,
    );
  }

  /// Writes every supported character-style property.
  static void _writeStyleProperties(
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
  static void _writeParagraphProperties(
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
  static void _writeSpacing(_PsdEngineWriter writer, PsdTextSpacing spacing) {
    writer.ascii(
      '${_engineNumber(spacing.minimum)} ${_engineNumber(spacing.desired)} ${_engineNumber(spacing.maximum)} ',
    );
  }

  /// Writes a numeric EngineData array body.
  static void _writeNumbers(_PsdEngineWriter writer, List<double> values) {
    for (final double value in values) {
      writer.ascii('${_engineNumber(value)} ');
    }
  }

  /// Writes a color dictionary without converting its original color space.
  static void _writeColor(_PsdEngineWriter writer, PsdTextColor color) {
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
  static void _writeResources(
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

  /// Encodes [text] using the byte order found in [original].
  static Uint8List _encodeEngineString(String text, Uint8List original) {
    final bool littleEndian = original.length >= 2 && original[0] == 0xff && original[1] == 0xfe;
    final BytesBuilder bytes = BytesBuilder(copy: false)..add(littleEndian ? const <int>[0xff, 0xfe] : const <int>[0xfe, 0xff]);
    for (final int unit in '$text\r'.codeUnits) {
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
  const _PsdNormalizedStyleRun({required this.length, required this.style});
}

/// A paragraph style and its normalized Photoshop run length.
final class _PsdNormalizedParagraph {
  /// Run length including the terminal character when this is the last run.
  final int length;

  /// Paragraph style written for the run.
  final PsdTextParagraph paragraph;

  /// Creates a normalized paragraph run.
  const _PsdNormalizedParagraph({required this.length, required this.paragraph});
}

/// Geometry decoded from the text engine's rendered tree.
final class _PsdTextShapeData {
  /// Point-text or box-text mode.
  final PsdTextShapeType type;

  /// Point-text anchor.
  final PsdTextPoint point;

  /// Box-text flow rectangle.
  final PsdTextBox box;

  /// Creates decoded text geometry.
  const _PsdTextShapeData({
    required this.type,
    required this.point,
    required this.box,
  });
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
PsDescriptor _createTextDescriptor(
  PsdTextContent content, {
  required PsdTextDescriptorBounds? descriptorBounds,
  required PsdTextDescriptorBounds? boundingBox,
  required int textIndex,
}) {
  final String text = content.text.replaceAll('\r\n', '\r').replaceAll('\n', '\r');
  return PsDescriptor(
    name: '',
    classId: 'TxLr',
    items: <PsDescriptorItem>[
      PsDescriptorItem(
        key: 'Txt ',
        value: PsStringValue(value: '$text\u0000'),
      ),
      PsDescriptorItem(
        key: 'textGridding',
        value: PsEnumeratedValue(
          typeId: 'textGridding',
          value: content.gridding == PsdTextGridding.round ? 'Rnd ' : 'None',
        ),
      ),
      PsDescriptorItem(
        key: 'Ornt',
        value: PsEnumeratedValue(typeId: 'Ornt', value: content.orientation == PsdTextOrientation.vertical ? 'Vrtc' : 'Hrzn'),
      ),
      PsDescriptorItem(
        key: 'AntA',
        value: PsEnumeratedValue(
          typeId: 'Annt',
          value: _encodeDescriptorAntiAlias(content.antiAlias),
        ),
      ),
      if (descriptorBounds != null)
        PsDescriptorItem(
          key: 'bounds',
          value: _createBoundsValue(descriptorBounds),
        ),
      if (boundingBox != null)
        PsDescriptorItem(
          key: 'boundingBox',
          value: _createBoundsValue(boundingBox),
        ),
      PsDescriptorItem(
        key: 'TextIndex',
        value: PsIntegerValue(value: textIndex),
      ),
      PsDescriptorItem(
        key: 'EngineData',
        value: PsRawValue(value: PsdTextEngine.encode(content)),
      ),
    ],
  );
}

/// Creates a descriptor for common [warp] settings.
PsDescriptor _createWarpDescriptor(PsdTextWarp warp) => PsDescriptor(
  name: '',
  classId: 'warp',
  items: <PsDescriptorItem>[
    PsDescriptorItem(
      key: 'warpStyle',
      value: PsEnumeratedValue(
        typeId: 'warpStyle',
        value: _encodeWarpStyle(warp.style),
      ),
    ),
    PsDescriptorItem(
      key: 'warpValue',
      value: PsDoubleValue(value: warp.value),
    ),
    PsDescriptorItem(
      key: 'warpPerspective',
      value: PsDoubleValue(value: warp.perspective),
    ),
    PsDescriptorItem(
      key: 'warpPerspectiveOther',
      value: PsDoubleValue(value: warp.perspectiveOther),
    ),
    PsDescriptorItem(
      key: 'warpRotate',
      value: PsEnumeratedValue(
        typeId: 'Ornt',
        value: warp.rotation == PsdTextOrientation.vertical ? 'Vrtc' : 'Hrzn',
      ),
    ),
  ],
);

/// Creates a Photoshop bounds descriptor from [bounds].
PsObjectValue _createBoundsValue(PsdTextDescriptorBounds bounds) => PsObjectValue(
  value: PsDescriptor(
    name: '',
    classId: 'bounds',
    items: <PsDescriptorItem>[
      PsDescriptorItem(
        key: 'Left',
        value: PsUnitFloatValue(unit: bounds.left.unit, value: bounds.left.value),
      ),
      PsDescriptorItem(
        key: 'Top ',
        value: PsUnitFloatValue(unit: bounds.top.unit, value: bounds.top.value),
      ),
      PsDescriptorItem(
        key: 'Rght',
        value: PsUnitFloatValue(unit: bounds.right.unit, value: bounds.right.value),
      ),
      PsDescriptorItem(
        key: 'Btom',
        value: PsUnitFloatValue(unit: bounds.bottom.unit, value: bounds.bottom.value),
      ),
    ],
  ),
);

/// Decodes descriptor bounds while retaining each edge's unit.
PsdTextDescriptorBounds? _readDescriptorBounds(PsDescriptorValue? value) {
  final PsDescriptor? descriptor = switch (value) {
    PsObjectValue(:final PsDescriptor value) => value,
    _ => null,
  };
  if (descriptor == null) {
    return null;
  }

  /// Reads one unit-bearing edge.
  PsdTextUnitValue? edge(String key) => switch (descriptor.value(key)) {
    PsUnitFloatValue(:final String unit, :final double value) => PsdTextUnitValue(unit: unit, value: value),
    _ => null,
  };

  final PsdTextUnitValue? left = edge('Left');
  final PsdTextUnitValue? top = edge('Top ');
  final PsdTextUnitValue? right = edge('Rght');
  final PsdTextUnitValue? bottom = edge('Btom');
  if (left == null || top == null || right == null || bottom == null) {
    return null;
  }
  return PsdTextDescriptorBounds(
    left: left,
    top: top,
    right: right,
    bottom: bottom,
  );
}

/// Reads a numeric action-descriptor value.
double? _descriptorNumber(PsDescriptorValue? value) => switch (value) {
  PsDoubleValue(:final double value) => value,
  PsIntegerValue(:final int value) => value.toDouble(),
  PsLargeIntegerValue(:final int value) => value.toDouble(),
  PsUnitFloatValue(:final double value) => value,
  _ => null,
};

/// Decodes common text-warp properties.
PsdTextWarp _readWarp(
  PsDescriptor descriptor, {
  required PsdTextOrientation fallbackRotation,
}) => PsdTextWarp(
  style: switch (descriptor.value('warpStyle')) {
    PsEnumeratedValue(:final String value) => _decodeWarpStyle(value),
    _ => PsdTextWarpStyle.none,
  },
  value: _descriptorNumber(descriptor.value('warpValue')) ?? 0,
  perspective: _descriptorNumber(descriptor.value('warpPerspective')) ?? 0,
  perspectiveOther: _descriptorNumber(descriptor.value('warpPerspectiveOther')) ?? 0,
  rotation: switch (descriptor.value('warpRotate')) {
    PsEnumeratedValue(:final String value) when value == 'Vrtc' => PsdTextOrientation.vertical,
    PsEnumeratedValue() => PsdTextOrientation.horizontal,
    _ => fallbackRotation,
  },
);

/// Updates common warp properties without dropping unknown descriptor keys.
PsDescriptor _updateWarpDescriptor(PsDescriptor descriptor, PsdTextWarp warp) => descriptor
    .withValue(
      'warpStyle',
      PsEnumeratedValue(
        typeId: 'warpStyle',
        value: _encodeWarpStyle(warp.style),
      ),
    )
    .withValue('warpValue', PsDoubleValue(value: warp.value))
    .withValue(
      'warpPerspective',
      PsDoubleValue(value: warp.perspective),
    )
    .withValue(
      'warpPerspectiveOther',
      PsDoubleValue(value: warp.perspectiveOther),
    )
    .withValue(
      'warpRotate',
      PsEnumeratedValue(
        typeId: 'Ornt',
        value: warp.rotation == PsdTextOrientation.vertical ? 'Vrtc' : 'Hrzn',
      ),
    );

/// Encodes a semantic warp style as an Adobe enumeration value.
String _encodeWarpStyle(PsdTextWarpStyle style) => switch (style) {
  PsdTextWarpStyle.none => 'warpNone',
  PsdTextWarpStyle.arc => 'warpArc',
  PsdTextWarpStyle.arcLower => 'warpArcLower',
  PsdTextWarpStyle.arcUpper => 'warpArcUpper',
  PsdTextWarpStyle.arch => 'warpArch',
  PsdTextWarpStyle.bulge => 'warpBulge',
  PsdTextWarpStyle.shellLower => 'warpShellLower',
  PsdTextWarpStyle.shellUpper => 'warpShellUpper',
  PsdTextWarpStyle.flag => 'warpFlag',
  PsdTextWarpStyle.wave => 'warpWave',
  PsdTextWarpStyle.fish => 'warpFish',
  PsdTextWarpStyle.rise => 'warpRise',
  PsdTextWarpStyle.fisheye => 'warpFisheye',
  PsdTextWarpStyle.inflate => 'warpInflate',
  PsdTextWarpStyle.squeeze => 'warpSqueeze',
  PsdTextWarpStyle.twist => 'warpTwist',
  PsdTextWarpStyle.cylinder => 'warpCylinder',
  PsdTextWarpStyle.custom => 'warpCustom',
};

/// Decodes an Adobe warp-style enumeration value.
PsdTextWarpStyle _decodeWarpStyle(String value) => switch (value) {
  'warpArc' => PsdTextWarpStyle.arc,
  'warpArcLower' => PsdTextWarpStyle.arcLower,
  'warpArcUpper' => PsdTextWarpStyle.arcUpper,
  'warpArch' => PsdTextWarpStyle.arch,
  'warpBulge' => PsdTextWarpStyle.bulge,
  'warpShellLower' => PsdTextWarpStyle.shellLower,
  'warpShellUpper' => PsdTextWarpStyle.shellUpper,
  'warpFlag' => PsdTextWarpStyle.flag,
  'warpWave' => PsdTextWarpStyle.wave,
  'warpFish' => PsdTextWarpStyle.fish,
  'warpRise' => PsdTextWarpStyle.rise,
  'warpFisheye' => PsdTextWarpStyle.fisheye,
  'warpInflate' => PsdTextWarpStyle.inflate,
  'warpSqueeze' => PsdTextWarpStyle.squeeze,
  'warpTwist' => PsdTextWarpStyle.twist,
  'warpCylinder' => PsdTextWarpStyle.cylinder,
  'warpCustom' => PsdTextWarpStyle.custom,
  _ => PsdTextWarpStyle.none,
};

/// Encodes an antialiasing mode for the surrounding action descriptor.
String _encodeDescriptorAntiAlias(PsdTextAntiAlias antiAlias) => switch (antiAlias) {
  PsdTextAntiAlias.none => 'Anno',
  PsdTextAntiAlias.sharp => 'antiAliasSharp',
  PsdTextAntiAlias.crisp => 'AnCr',
  PsdTextAntiAlias.strong => 'AnSt',
  PsdTextAntiAlias.smooth => 'AnSm',
  PsdTextAntiAlias.platform => 'antiAliasPlatformGray',
  PsdTextAntiAlias.platformLcd => 'antiAliasPlatformLCD',
};

/// Decodes an antialiasing mode from the surrounding action descriptor.
PsdTextAntiAlias _decodeDescriptorAntiAlias(PsDescriptorValue? value) {
  final String? encoded = switch (value) {
    PsEnumeratedValue(:final String value) => value,
    _ => null,
  };
  return switch (encoded) {
    'Anno' => PsdTextAntiAlias.none,
    'AnCr' => PsdTextAntiAlias.crisp,
    'AnSt' => PsdTextAntiAlias.strong,
    'AnSm' => PsdTextAntiAlias.smooth,
    'antiAliasPlatformGray' => PsdTextAntiAlias.platform,
    'antiAliasPlatformLCD' => PsdTextAntiAlias.platformLcd,
    _ => PsdTextAntiAlias.sharp,
  };
}

/// Encodes an antialiasing mode for Adobe text-engine data.
int _encodeEngineAntiAlias(PsdTextAntiAlias antiAlias) => switch (antiAlias) {
  PsdTextAntiAlias.none => 0,
  PsdTextAntiAlias.crisp => 1,
  PsdTextAntiAlias.strong => 2,
  PsdTextAntiAlias.smooth => 3,
  PsdTextAntiAlias.sharp || PsdTextAntiAlias.platform || PsdTextAntiAlias.platformLcd => 4,
};

/// Decodes an antialiasing index from Adobe text-engine data.
PsdTextAntiAlias _decodeEngineAntiAlias(
  int? value, {
  required PsdTextAntiAlias fallback,
}) => switch (value) {
  0 => PsdTextAntiAlias.none,
  1 => PsdTextAntiAlias.crisp,
  2 => PsdTextAntiAlias.strong,
  3 => PsdTextAntiAlias.smooth,
  4 => PsdTextAntiAlias.sharp,
  _ => fallback,
};

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

/// Normalizes sparse semantic [runs] into contiguous Photoshop style runs.
List<_PsdNormalizedStyleRun> _normalizeStyles(List<PsdTextStyleRun> runs, int textLength) {
  const PsdTextStyle fallback = PsdTextStyle(fontFamily: 'ArialMT', fontSize: 12, color: PsdTextColor(alpha: 255, red: 0, green: 0, blue: 0));
  if (runs.isEmpty || textLength == 0) {
    return <_PsdNormalizedStyleRun>[
      _PsdNormalizedStyleRun(
        length: textLength + 1,
        style: runs.isEmpty ? fallback : runs.first.style,
      ),
    ];
  }
  final List<PsdTextStyleRun> sorted = List<PsdTextStyleRun>.of(runs)..sort((left, right) => left.start.compareTo(right.start));
  final List<_PsdNormalizedStyleRun> result = <_PsdNormalizedStyleRun>[];
  PsdTextStyle current = sorted.first.style;
  int offset = 0;
  for (final PsdTextStyleRun run in sorted) {
    final int start = run.start.clamp(offset, textLength);
    if (start > offset) {
      result.add(_PsdNormalizedStyleRun(length: start - offset, style: current));
    }
    final int end = (run.start + run.length).clamp(start, textLength);
    if (end > start) {
      result.add(_PsdNormalizedStyleRun(length: end - start, style: run.style));
    }
    current = run.style;
    offset = end;
  }
  if (offset < textLength) {
    result.add(_PsdNormalizedStyleRun(length: textLength - offset, style: current));
  }
  if (result.isEmpty) {
    result.add(_PsdNormalizedStyleRun(length: textLength, style: current));
  }
  final _PsdNormalizedStyleRun last = result.removeLast();
  result.add(_PsdNormalizedStyleRun(length: last.length + 1, style: last.style));
  return result;
}

/// Normalizes sparse semantic [paragraphs] into contiguous Photoshop runs.
List<_PsdNormalizedParagraph> _normalizeParagraphs(List<PsdTextParagraph> paragraphs, int textLength) {
  if (paragraphs.isEmpty || textLength == 0) {
    return <_PsdNormalizedParagraph>[
      _PsdNormalizedParagraph(
        length: textLength + 1,
        paragraph: paragraphs.isEmpty
            ? const PsdTextParagraph(
                start: 0,
                length: 0,
                justification: PsdTextJustification.left,
              )
            : paragraphs.first,
      ),
    ];
  }
  final List<PsdTextParagraph> sorted = List<PsdTextParagraph>.of(paragraphs)..sort((left, right) => left.start.compareTo(right.start));
  final List<_PsdNormalizedParagraph> result = <_PsdNormalizedParagraph>[];
  PsdTextParagraph current = sorted.first;
  int offset = 0;
  for (final PsdTextParagraph paragraph in sorted) {
    final int start = paragraph.start.clamp(offset, textLength);
    if (start > offset) {
      result.add(_PsdNormalizedParagraph(length: start - offset, paragraph: current));
    }
    final int end = (paragraph.start + paragraph.length).clamp(start, textLength);
    if (end > start) {
      result.add(
        _PsdNormalizedParagraph(
          length: end - start,
          paragraph: paragraph,
        ),
      );
    }
    current = paragraph;
    offset = end;
  }
  if (offset < textLength) {
    result.add(_PsdNormalizedParagraph(length: textLength - offset, paragraph: current));
  }
  if (result.isEmpty) {
    result.add(_PsdNormalizedParagraph(length: textLength, paragraph: current));
  }
  final _PsdNormalizedParagraph last = result.removeLast();
  result.add(
    _PsdNormalizedParagraph(
      length: last.length + 1,
      paragraph: last.paragraph,
    ),
  );
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
  const _PsdEngineDictionary({required this.values});

  /// Returns the value associated with [key].
  Object? operator [](String key) => values[key];
}

/// A byte string parsed from Adobe text-engine data.
final class _PsdEngineString {
  /// Unescaped string bytes.
  final Uint8List bytes;

  /// Creates a binary engine string.
  const _PsdEngineString({required this.bytes});
}

/// A PostScript name used as a dictionary value.
final class _PsdEngineName {
  /// Name without its leading slash.
  final String value;

  /// Creates an engine name.
  const _PsdEngineName({required this.value});
}

/// Bounded parser for the PostScript subset used by Adobe `EngineData`.
final class _PsdEngineParser {
  /// Bytes being parsed.
  final Uint8List _bytes;

  /// Current byte offset.
  int _offset;

  /// Number of dictionaries and arrays currently open.
  int _depth = 0;

  /// Creates an engine-data parser.
  _PsdEngineParser({required this._bytes, this._offset = 0});

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
          return _PsdEngineString(bytes: value.takeBytes());
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
      return _PsdEngineName(value: _readName());
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
    _enter();
    _offset += 2;
    final Map<String, Object?> values = <String, Object?>{};
    while (true) {
      _skipTrivia();
      if (_startsWith('>>')) {
        _offset += 2;
        _depth--;
        return _PsdEngineDictionary(values: values);
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
    _enter();
    _offset++;
    final List<Object?> values = <Object?>[];
    while (true) {
      _skipTrivia();
      if (_offset >= _bytes.length) {
        throw const FormatException('Unterminated EngineData array');
      }
      if (_bytes[_offset] == 0x5d) {
        _offset++;
        _depth--;
        return values;
      }
      values.add(_readValue());
    }
  }

  /// Opens one nesting level, rejecting input that would exhaust the stack.
  void _enter() {
    if (++_depth > _maximumEngineDepth) {
      throw const FormatException('EngineData nesting exceeds the supported depth');
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

/// Returns the dictionary at [index] in [value], when present.
_PsdEngineDictionary? _dictionaryAt(Object? value, int index) {
  final List<Object?>? values = _list(value);
  return values != null && index >= 0 && index < values.length ? _dictionary(values[index]) : null;
}

/// Extracts character-style data from a style-run or resource entry.
_PsdEngineDictionary? _styleData(_PsdEngineDictionary? value) {
  final _PsdEngineDictionary? sheet = _dictionary(value?['StyleSheet']);
  return _dictionary(sheet?['StyleSheetData']) ?? _dictionary(value?['StyleSheetData']);
}

/// Returns a resource character-style sheet by [index].
_PsdEngineDictionary? _resourceStyleData(
  _PsdEngineDictionary? resources,
  int index,
) => _dictionary(_dictionaryAt(resources?['StyleSheetSet'], index)?['StyleSheetData']);

/// Returns a resource paragraph-style sheet by [index].
_PsdEngineDictionary? _resourceParagraphData(
  _PsdEngineDictionary? resources,
  int index,
) => _dictionary(_dictionaryAt(resources?['ParagraphSheetSet'], index)?['Properties']);

/// Merges inherited EngineData dictionaries from least to most specific.
_PsdEngineDictionary _mergeDictionaries(List<_PsdEngineDictionary?> dictionaries) {
  final Map<String, Object?> values = <String, Object?>{};
  for (final _PsdEngineDictionary? dictionary in dictionaries) {
    if (dictionary != null) {
      values.addAll(dictionary.values);
    }
  }
  return _PsdEngineDictionary(values: values);
}

/// Converts an engine array into numeric values.
List<double>? _numbers(Object? value) {
  final List<Object?>? values = _list(value);
  if (values == null || values.any((entry) => entry is! num)) {
    return null;
  }
  return <double>[for (final Object? entry in values) (entry! as num).toDouble()];
}

/// Reads a spacing triplet, falling back when the value is absent or malformed.
PsdTextSpacing _readSpacing(
  Object? value, {
  required PsdTextSpacing fallback,
}) {
  final List<double>? values = _numbers(value);
  return values != null && values.length >= 3
      ? PsdTextSpacing(
          minimum: values[0],
          desired: values[1],
          maximum: values[2],
        )
      : fallback;
}

/// Converts an engine numeric value to a double.
double? _number(Object? value) => value is num ? value.toDouble() : null;

/// Converts an engine numeric value to an integer.
int? _integer(Object? value) => value is num ? value.toInt() : null;

/// Converts Boolean and historical zero-or-one engine values to a Boolean.
bool? _engineBoolean(Object? value) => value is bool
    ? value
    : value is num
    ? value != 0
    : null;

/// Removes the required final paragraph mark from an EngineData editor string.
String _withoutEngineTerminator(String value) {
  final String withoutNull = _withoutTerminalNull(value);
  return withoutNull.endsWith('\r') ? withoutNull.substring(0, withoutNull.length - 1) : withoutNull;
}

/// Converts private parser nodes into immutable public values.
Object? _publicEngineValue(Object? value) {
  if (value is _PsdEngineDictionary) {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final MapEntry<String, Object?> entry in value.values.entries) entry.key: _publicEngineValue(entry.value),
    });
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(<Object?>[
      for (final Object? entry in value) _publicEngineValue(entry),
    ]);
  }
  if (value is _PsdEngineString) {
    return _decodeEngineString(value) ?? Uint8List.fromList(value.bytes);
  }
  if (value is _PsdEngineName) {
    return PsdTextEngineName(value: value.value);
  }
  return value;
}

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
    final _PsdEngineParser parser = _PsdEngineParser(bytes: source, offset: offset);
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
