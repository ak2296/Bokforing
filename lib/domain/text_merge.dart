import 'dart:math' as math;

/// Joins OCR text from several photos of one long document. If the last rows
/// of one part are repeated at the start of the next (the photos overlap),
/// the repeated rows are kept only once. Rows are compared ignoring spacing
/// and punctuation and tolerating small OCR differences.
String mergeParts(List<String> parts) {
  if (parts.isEmpty) return '';
  var out = parts.first.split('\n');
  for (final part in parts.skip(1)) {
    final next = part.split('\n');
    out = [...out, ...next.skip(_overlap(out, next))];
  }
  return out.join('\n');
}

String _key(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9åäö]'), '');

bool _similar(String a, String b) {
  if (a == b) return true;
  final longest = math.max(a.length, b.length);
  if (longest < 4) return false;
  return _distance(a, b) <= longest * 0.15;
}

int _overlap(List<String> a, List<String> b) {
  final max = math.min(math.min(a.length, b.length), 12);
  for (var k = max; k >= 1; k--) {
    var ok = true;
    var chars = 0;
    for (var i = 0; i < k; i++) {
      final x = _key(a[a.length - k + i]), y = _key(b[i]);
      if (!_similar(x, y)) {
        ok = false;
        break;
      }
      chars += x.length;
    }
    // Rows of only dashes or a few characters are not evidence of overlap.
    if (ok && chars >= 10) return k;
  }
  return 0;
}

int _distance(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1),
          prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
    }
    prev = cur;
  }
  return prev[b.length];
}
