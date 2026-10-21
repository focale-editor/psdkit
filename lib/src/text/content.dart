part of '../text.dart';

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

  /// Whether [shapeType], [pointBase], and [boxBounds] were present in the source.
  ///
  /// Older writers may omit the rendered shape tree. Consumers can then use a
  /// format-specific compatibility fallback without mistaking an explicit
  /// point-text record for missing geometry.
  final bool hasShapeMetadata;

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
    this.hasShapeMetadata = true,
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
