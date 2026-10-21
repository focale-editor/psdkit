part of '../text.dart';

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
