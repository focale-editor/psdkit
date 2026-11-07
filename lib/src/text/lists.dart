part of '../text.dart';

/// Photoshop's predefined list resources, in their standard resource order.
enum PsdTextListStyle {
  /// Decimal numbering.
  numeric('kPredefinedNumericListStyleTag'),

  /// Uppercase alphabetic numbering.
  upperAlpha('kPredefinedUppercaseAlphaListStyleTag'),

  /// Lowercase alphabetic numbering.
  lowerAlpha('kPredefinedLowercaseAlphaListStyleTag'),

  /// Uppercase Roman numbering.
  upperRoman('kPredefinedUppercaseRomanNumListStyleTag'),

  /// Lowercase Roman numbering.
  lowerRoman('kPredefinedLowercaseRomanNumListStyleTag'),

  /// Filled circular bullets.
  bullet('kPredefinedBulletListStyleTag'),

  /// Dash bullets.
  dash('kPredefinedDashBulletListStyleTag'),

  /// Empty circular bullets.
  emptyCircle('kPredefinedEmptyCircleBulletListStyleTag'),

  /// Filled square bullets.
  filledSquare('kPredefinedFilledSquareBulletListStyleTag'),

  /// Decimal numbering with one leading zero.
  numericOneZero('kPredefinedSingleZeroPrefixNumericListStyleTag'),

  /// Decimal numbering with two leading zeros.
  numericTwoZeros('kPredefinedDoubleZeroPrefixNumericListStyleTag');

  /// Stable tag, resolved independently of a document's resource indices.
  final String tag;

  /// Associates a predefined resource with its native tag.
  const PsdTextListStyle(this.tag);
}

/// Native generated paragraph markers, absent from the plain text and TySh.
final class PsdTextList {
  /// Predefined marker family.
  final PsdTextListStyle style;

  /// Zero-based nesting tier, which also selects Photoshop's marker variant.
  final int tier;

  /// Creates a predefined native list reference.
  const PsdTextList({required this.style, this.tier = 0});
}

/// Resolves generated lists while preserving each local paragraph's formatting.
PsdTextContent _applyGlobalLists(_PsdEngineDictionary root, Object? object, PsdTextContent content) {
  final List<Object?>? runs = _list(_globalPath(object, ['0', '5', '0']));
  if (runs == null) {
    return content;
  }
  final List<Object?>? resources = _list(_globalPath(root, ['0', '9', '0']));
  final List<PsdTextParagraph> paragraphs = [];
  int offset = 0;
  for (final Object? run in runs) {
    final int? length = _integer(_globalPath(run, ['1']));
    if (length == null || length < 0) {
      return content.copyWith(hasUnsupportedGeometry: true);
    }
    final int end = (offset + length).clamp(offset, content.text.length);
    final _PsdEngineDictionary? sheet = _globalParagraphSheet(root, _globalPath(run, ['0', '0']));
    if (sheet == null) {
      return content.copyWith(hasUnsupportedGeometry: true);
    }
    final Object? rawReference = sheet['36'];
    final Object? reference = rawReference is _PsdEngineName && rawReference.value == 'nil' ? null : rawReference;
    final int? index = _integer(reference);
    final int tier = _integer(sheet['37']) ?? 0;
    final String? tag = index != null && resources != null && index >= 0 && index < resources.length ? _decodeEngineString(_globalPath(resources[index], ['0', '0'])) : null;
    final PsdTextListStyle? style = PsdTextListStyle.values.where((style) => style.tag == tag).firstOrNull;
    final bool unsupported = reference != null && (style == null || tier < 0 || tier > 8 || sheet['37'] != null && _integer(sheet['37']) == null);
    while (offset < end) {
      final PsdTextParagraph local =
          content.paragraphs.where((paragraph) => paragraph.start <= offset && paragraph.start + paragraph.length > offset).firstOrNull ??
          PsdTextParagraph(start: offset, length: end - offset, justification: PsdTextJustification.left);
      final int pieceEnd = (local.start + local.length).clamp(offset + 1, end);
      paragraphs.add(
        local.copyWith(
          start: offset,
          length: pieceEnd - offset,
          list: style == null ? null : PsdTextList(style: style, tier: tier),
          hasUnsupportedList: unsupported,
        ),
      );
      offset = pieceEnd;
    }
  }
  return offset == content.text.length ? content.copyWith(paragraphs: List.unmodifiable(paragraphs)) : content.copyWith(hasUnsupportedGeometry: true);
}

/// Resolves an inline paragraph sheet and its named resource before defaults.
_PsdEngineDictionary? _globalParagraphSheet(_PsdEngineDictionary root, Object? selection) {
  final List<Object?>? styles = _list(_globalPath(root, ['0', '6', '0']));
  final _PsdEngineDictionary? inline = _dictionary(selection);
  final Object? reference = selection is int ? selection : inline?['6'];
  final int? index = _integer(reference);
  if (reference != null && (index == null || styles == null || index < 0 || index >= styles.length)) {
    return null;
  }
  final _PsdEngineDictionary? named = index == null ? null : _dictionary(_globalPath(styles![index], ['0', '5']));
  if (index != null && named == null) {
    return null;
  }
  // A named sheet's /6 selects a character style, not another paragraph parent.
  return _globalDictionary({
    ...?_dictionary(_globalPath(root, ['1', '3']))?.values,
    ...?named?.values,
    ...?_dictionary(inline?['5'])?.values,
  });
}
