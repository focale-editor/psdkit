part of '../text.dart';

/// A UTF-16 range carrying character, paragraph, or raw engine properties.
typedef _PsdTextRange<T> = ({int start, int length, T value});

/// Properties and stored length, including the final paragraph mark when last.
typedef _PsdTextRun<T> = ({int length, T value});

/// Normalizes character styles while retaining Photoshop's default font.
List<_PsdTextRun<PsdTextStyle>> _normalizeStyles(List<PsdTextStyleRun> runs, int textLength) => _normalizeRuns(
  [for (final PsdTextStyleRun run in runs) (start: run.start, length: run.length, value: run.style)],
  textLength: textLength,
  fallback: const PsdTextStyle(fontFamily: 'ArialMT', fontSize: 12, color: PsdTextColor(alpha: 255, red: 0, green: 0, blue: 0)),
);

/// Normalizes paragraph styles with left alignment as the default.
List<_PsdTextRun<PsdTextParagraph>> _normalizeParagraphs(List<PsdTextParagraph> paragraphs, int textLength) => _normalizeRuns(
  [for (final PsdTextParagraph paragraph in paragraphs) (start: paragraph.start, length: paragraph.length, value: paragraph)],
  textLength: textLength,
  fallback: const PsdTextParagraph(start: 0, length: 0, justification: .left),
);

/// Clips overlaps, fills gaps with the preceding style, and adds the terminator.
///
/// Empty text retains the first supplied style before sorting. Empty ranges
/// still select the style of the following gap.
List<_PsdTextRun<T>> _normalizeRuns<T>(List<_PsdTextRange<T>> runs, {required int textLength, required T fallback}) {
  if (runs.isEmpty || textLength == 0) {
    return [(length: textLength + 1, value: runs.isEmpty ? fallback : runs.first.value)];
  }
  final List<_PsdTextRange<T>> sorted = List.of(runs)..sort((left, right) => left.start.compareTo(right.start));
  final List<_PsdTextRun<T>> result = [];
  T current = sorted.first.value;
  int offset = 0;
  for (final _PsdTextRange<T> run in sorted) {
    final int start = run.start.clamp(offset, textLength);
    if (start > offset) {
      result.add((length: start - offset, value: current));
    }
    final int end = (run.start + run.length).clamp(start, textLength);
    if (end > start) {
      result.add((length: end - start, value: run.value));
    }
    current = run.value;
    offset = end;
  }
  if (offset < textLength) {
    result.add((length: textLength - offset, value: current));
  }
  if (result.isEmpty) {
    result.add((length: textLength, value: current));
  }
  final _PsdTextRun<T> last = result.removeLast();
  result.add((length: last.length + 1, value: last.value));
  return result;
}

/// Reads paired run arrays, clipping lengths to the logical UTF-16 text.
///
/// Missing arrays yield no runs. A nonpositive or nonnumeric length ends the
/// sequence, and unmatched entries in either array are ignored.
Iterable<_PsdTextRange<_PsdEngineDictionary?>> _readEngineRuns(_PsdEngineDictionary? runs, {required int textLength}) sync* {
  final List<Object?>? lengths = _list(runs?['RunLengthArray']);
  final List<Object?>? values = _list(runs?['RunArray']);
  if (lengths == null || values == null) {
    return;
  }
  int start = 0;
  for (int index = 0; index < lengths.length && index < values.length && start < textLength; index++) {
    final int storedLength = _integer(lengths[index]) ?? 0;
    final int length = storedLength.clamp(0, textLength - start);
    if (length == 0) {
      return;
    }
    yield (start: start, length: length, value: _dictionary(values[index]));
    start += length;
  }
}
