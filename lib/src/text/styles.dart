part of '../text.dart';

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
  grayscale(engineType: 0, componentCount: 1),

  /// Red, green, and blue components.
  rgb(engineType: 1, componentCount: 3),

  /// Cyan, magenta, yellow, and black components.
  cmyk(engineType: 2, componentCount: 4);

  /// Adobe text-engine `Type` of a color in this space.
  final int engineType;

  /// Number of components, without alpha.
  final int componentCount;

  /// Creates a color space with its engine type and component count.
  const PsdTextColorSpace({required this.engineType, required this.componentCount});
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

  /// Adobe's normalized `Values` at full precision, when known.
  ///
  /// Alpha comes first, then the components of [colorSpace]: one gray, three
  /// RGB or four CMYK values, each from 0 through 1. The integer fields round
  /// them to 8 bits; writing prefers these values when present.
  final List<double>? values;

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
       black = null,
       values = null;

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
      black = null,
      values = null;

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

  /// Creates a color from Adobe's normalized `Values` in [colorSpace].
  ///
  /// [values] holds alpha, then the components of [colorSpace]; see
  /// [PsdTextColor.values]. They are kept at full precision.
  factory PsdTextColor.fromValues(PsdTextColorSpace colorSpace, List<double> values) {
    final int count = colorSpace.componentCount + 1;
    if (values.length != count || values.any((value) => !value.isFinite)) {
      throw ArgumentError.value(values, 'values', '${colorSpace.name} needs $count finite values');
    }
    final List<double> normalized = List.unmodifiable([for (final double value in values) value.clamp(0, 1).toDouble()]);
    int channel(int index) => (normalized[index] * 255).round();
    final PsdTextColor rounded = switch (colorSpace) {
      PsdTextColorSpace.grayscale => PsdTextColor.grayscale(alpha: channel(0), value: channel(1)),
      PsdTextColorSpace.rgb => PsdTextColor(alpha: channel(0), red: channel(1), green: channel(2), blue: channel(3)),
      PsdTextColorSpace.cmyk => PsdTextColor.cmyk(alpha: channel(0), cyan: channel(1), magenta: channel(2), yellow: channel(3), black: channel(4)),
    };
    return PsdTextColor._(
      colorSpace: colorSpace,
      alpha: rounded.alpha,
      red: rounded.red,
      green: rounded.green,
      blue: rounded.blue,
      gray: rounded.gray,
      cyan: rounded.cyan,
      magenta: rounded.magenta,
      yellow: rounded.yellow,
      black: rounded.black,
      values: normalized,
    );
  }

  /// Creates a color with already resolved preview and source components.
  const PsdTextColor._({
    required this.colorSpace,
    required this.alpha,
    required this.red,
    required this.green,
    required this.blue,
    this.gray,
    this.cyan,
    this.magenta,
    this.yellow,
    this.black,
    this.values,
  });

  /// The color packed as an ARGB integer.
  int get argb => alpha << 24 | red << 16 | green << 8 | blue;
}

/// Automatic pair-spacing method recorded by Photoshop's global text engine.
enum PsdTextKerning {
  /// Uses explicit kerning amounts.
  manual,

  /// Uses the font's kerning metrics.
  metrics,

  /// Uses Photoshop's optical spacing algorithm.
  optical,
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

  /// Exact global-engine mode, when known; takes precedence over [automaticKerning].
  final PsdTextKerning? kerningMode;

  /// OpenType feature values, keyed by four-character tags such as `calt` or `ss01`.
  final Map<String, int> openTypeFeatures;

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
    this.kerningMode,
    this.openTypeFeatures = const {},
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

  /// Exact kerning mode or the legacy EngineData interpretation.
  PsdTextKerning get resolvedKerningMode => kerningMode ?? (automaticKerning ? PsdTextKerning.metrics : PsdTextKerning.manual);

  /// Copies formatting while replacing the requested non-null properties.
  PsdTextStyle copyWith({
    String? fontFamily,
    PsdTextFont? font,
    double? fontSize,
    PsdTextColor? color,
    double? tracking,
    double? lineHeight,
    bool? automaticLeading,
    double? horizontalScale,
    double? verticalScale,
    bool? automaticKerning,
    PsdTextKerning? kerningMode,
    Map<String, int>? openTypeFeatures,
    double? kerning,
    double? baselineShift,
    int? fontCaps,
    int? fontBaseline,
    bool? fauxBold,
    bool? fauxItalic,
    bool? underline,
    bool? strikethrough,
    bool? ligatures,
    bool? discretionaryLigatures,
    int? baselineDirection,
    double? tsume,
    int? styleRunAlignment,
    int? language,
    bool? noBreak,
    PsdTextColor? strokeColor,
    bool? fillEnabled,
    bool? strokeEnabled,
    bool? fillFirst,
    double? underlinePosition,
    double? outlineWidth,
    int? characterDirection,
    bool? hindiNumbers,
    int? kashida,
    int? diacriticPosition,
  }) => PsdTextStyle(
    fontFamily: fontFamily ?? this.fontFamily,
    font: font ?? (fontFamily == null ? this.font : null),
    fontSize: fontSize ?? this.fontSize,
    color: color ?? this.color,
    tracking: tracking ?? this.tracking,
    lineHeight: lineHeight ?? this.lineHeight,
    automaticLeading: automaticLeading ?? this.automaticLeading,
    horizontalScale: horizontalScale ?? this.horizontalScale,
    verticalScale: verticalScale ?? this.verticalScale,
    automaticKerning: automaticKerning ?? this.automaticKerning,
    kerningMode: kerningMode ?? (automaticKerning == null ? this.kerningMode : null),
    openTypeFeatures: openTypeFeatures ?? this.openTypeFeatures,
    kerning: kerning ?? this.kerning,
    baselineShift: baselineShift ?? this.baselineShift,
    fontCaps: fontCaps ?? this.fontCaps,
    fontBaseline: fontBaseline ?? this.fontBaseline,
    fauxBold: fauxBold ?? this.fauxBold,
    fauxItalic: fauxItalic ?? this.fauxItalic,
    underline: underline ?? this.underline,
    strikethrough: strikethrough ?? this.strikethrough,
    ligatures: ligatures ?? this.ligatures,
    discretionaryLigatures: discretionaryLigatures ?? this.discretionaryLigatures,
    baselineDirection: baselineDirection ?? this.baselineDirection,
    tsume: tsume ?? this.tsume,
    styleRunAlignment: styleRunAlignment ?? this.styleRunAlignment,
    language: language ?? this.language,
    noBreak: noBreak ?? this.noBreak,
    strokeColor: strokeColor ?? this.strokeColor,
    fillEnabled: fillEnabled ?? this.fillEnabled,
    strokeEnabled: strokeEnabled ?? this.strokeEnabled,
    fillFirst: fillFirst ?? this.fillFirst,
    underlinePosition: underlinePosition ?? this.underlinePosition,
    outlineWidth: outlineWidth ?? this.outlineWidth,
    characterDirection: characterDirection ?? this.characterDirection,
    hindiNumbers: hindiNumbers ?? this.hindiNumbers,
    kashida: kashida ?? this.kashida,
    diacriticPosition: diacriticPosition ?? this.diacriticPosition,
  );

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
