import 'ocr_models.dart';
import 'text_patterns.dart';

/// Joins several photos of one long document (top to bottom) into one text.
/// Rows repeated at the overlap between two photos are kept only once.
class TextMerge {
  const TextMerge._();

  static OcrResult merge(List<OcrResult> parts) {
    if (parts.length == 1) return parts.single;
    final rows = <String>[];
    for (final part in parts) {
      final next = part.rows().map((r) => r.text).toList();
      final overlap = _overlap(rows, next);
      rows.addAll(next.skip(overlap));
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
}
