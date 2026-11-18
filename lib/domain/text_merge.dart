import 'money.dart';
import 'ocr_models.dart';
import 'text_patterns.dart';

/// Joins several photos of one long document (top to bottom) into one text.
/// Rows repeated at the overlap between two photos are kept only once.
class TextMerge {
  const TextMerge._();

  static OcrResult merge(List<OcrResult> parts) {
    if (parts.length == 1) return parts.single;
    var rows = <String>[];
    for (final part in parts) {
      final next = part.rows().map((r) => r.text).toList();
      final overlap = _overlap(rows, next);
      if (overlap > 0) {
        rows.addAll(next.skip(overlap));
        continue;
      }
      final cut = _fuzzyOverlap(rows, next);
      rows = cut == null ? [...rows, ...next] : [...rows.take(cut.$1 + 1), ...next.skip(cut.$2 + 1)];
    }
    return OcrResult.fromPlainText(rows.join('\n'));
  }

  /// Largest k such that the last k rows of [a] match the first k of [b].
  static int _overlap(List<String> a, List<String> b) {
    final maxK = [a.length, b.length, 12].reduce((x, y) => x < y ? x : y);
    for (var k = maxK; k >= 1; k--) {
      var ok = true;
      for (var i = 0; i < k; i++) {
        final x = TextPatterns.normalize(a[a.length - k + i]);
        final y = TextPatterns.normalize(b[i]);
        if (x != y && TextPatterns.similarity(x, y) < 0.85) {
          ok = false;
          break;
        }
      }
      if (ok) return k;
    }
    return 0;
  }

  /// How far back and forward an overlap is looked for, in rows.
  static const _window = 120;

  /// The edge of a photo reads worst, so the two readings of the overlap
  /// differ ("Kontanter" against "Kontantu"). Rows are matched loosely, in
  /// order: similar text, or the same amount. The overlap must start near
  /// the top of [b] and reach near the bottom of [a]. Returns the pair of
  /// rows (index in [a], index in [b]) in the middle of the overlap, where
  /// both photos read best: [a] is kept up to it and [b] after it. Null
  /// when the photos do not overlap.
  static (int, int)? _fuzzyOverlap(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return null;
    final from = a.length > _window ? a.length - _window : 0;
    final tail = [for (final r in a.skip(from)) _Row(r)];
    final head = [for (final r in b.take(_window)) _Row(r)];
    // Longest chain of matching rows in order (LCS).
    final n = tail.length, m = head.length;
    final best = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        best[i][j] = tail[i].matches(head[j])
            ? best[i + 1][j + 1] + 1
            : (best[i + 1][j] > best[i][j + 1] ? best[i + 1][j] : best[i][j + 1]);
      }
    }
    final pairs = <(int, int)>[];
    for (var i = 0, j = 0; i < n && j < m;) {
      if (tail[i].matches(head[j]) && best[i][j] == best[i + 1][j + 1] + 1) {
        pairs.add((i, j));
        i++;
        j++;
      } else if (best[i + 1][j] >= best[i][j + 1]) {
        i++;
      } else {
        j++;
      }
    }
    if (pairs.length < 3) return null;
    final spanA = pairs.last.$1 - pairs.first.$1 + 1, spanB = pairs.last.$2 - pairs.first.$2 + 1;
    final shorter = spanA < spanB ? spanA : spanB;
    final dense = pairs.length * 10 >= shorter * 3;
    final atEnd = n - 1 - pairs.last.$1 <= 12;
    final atStart = pairs.first.$2 <= 12;
    // Two pages that both start with the letterhead are not one overlap.
    final belowTop = from + pairs.first.$1 >= 3;
    if (!dense || !atEnd || !atStart || !belowTop) return null;
    final mid = pairs[pairs.length ~/ 2];
    return (from + mid.$1, mid.$2);
  }
}

class _Row {
  final String norm;
  final Money? amount;
  _Row(String text)
      : norm = TextPatterns.normalize(text),
        amount = TextPatterns.amounts(text).lastOrNull?.value;

  bool get _meaningful => norm.replaceAll(RegExp(r'[^a-zåäö0-9]'), '').length >= 4;

  /// Same row read twice: close text, or the same amount that is not zero.
  bool matches(_Row o) {
    if (!_meaningful || !o._meaningful) return false;
    if (amount != null && o.amount != null && !amount!.isZero && amount == o.amount) return true;
    return TextPatterns.similarity(norm, o.norm) >= 0.7;
  }
}
