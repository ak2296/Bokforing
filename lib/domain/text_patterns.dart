import 'dates.dart';
import 'money.dart';
import 'vat.dart';

enum Confidence { high, medium, low }

extension ConfidenceText on Confidence {
  String get label => switch (this) {
        Confidence.high => 'Säker',
        Confidence.medium => 'Kontrollera',
        Confidence.low => 'Osäker',
      };
}

/// A value read from the document with how sure the reader is and where it
/// came from.
class Extracted<T> {
  final T? value;
  final Confidence confidence;
  final String? source;
  final String? note;
  const Extracted(this.value, this.confidence, {this.source, this.note});
  const Extracted.none() : value = null, confidence = Confidence.low, source = null, note = null;

  bool get hasValue => value != null;
}

/// A monetary amount found in a row, with its character position.
class AmountToken {
  final Money value;
  final int start;
  final int end;
  final bool hasDecimals;
  const AmountToken(this.value, this.start, this.end, this.hasDecimals);
}

class TextPatterns {
  const TextPatterns._();

  /// Lowercase, collapse spaces, fold common OCR confusions in words.
  static String normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  // Grouped thousands with decimals, plain decimals, `125:-`, plain integers.
  static final _amount = RegExp(
      r'(?<![\d.,])-?(?:\d{1,3}(?:[  .]\d{3})+(?:[,.]\d{1,2})?|\d+[,.]\d{1,2}|\d+:-|\d+)(?:-)?(?![\d%])');

  /// Amounts in a row, skipping dates, percentages and long digit runs
  /// (invoice numbers, OCR numbers, phone numbers).
  static List<AmountToken> amounts(String row) {
    final masked = _maskNonAmounts(row);
    final out = <AmountToken>[];
    for (final m in _amount.allMatches(masked)) {
      var raw = m.group(0)!;
      if (raw.trim().isEmpty) continue;
      // A grouped match like "23 1 912,00" splits wrongly; prefer the longest
      // valid amount that ends at this match end.
      final hasDecimals = RegExp(r'[,.]\d{1,2}-?$').hasMatch(raw) || raw.endsWith(':-');
      final digitsOnly = raw.replaceAll(RegExp(r'[^\d]'), '');
      if (!hasDecimals && digitsOnly.length > 7) continue;
      raw = raw.trim();
      final v = Money.parse(raw);
      if (v == null) continue;
      out.add(AmountToken(v, m.start, m.end, hasDecimals));
    }
    return out;
  }

  /// Replaces dates, percentages, times and long digit runs with spaces so
  /// they are never read as amounts.
  static String _maskNonAmounts(String row) {
    var s = row;
    String blank(Match m) => ' ' * m.group(0)!.length;
    s = s.replaceAllMapped(RegExp(r'\d{4}[-./]\d{1,2}[-./]\d{1,2}'), blank);
    s = s.replaceAllMapped(RegExp(r'\b\d{1,2}[-./]\d{1,2}[-./]\d{2,4}\b'), blank);
    s = s.replaceAllMapped(RegExp(r'\b\d{1,2}:\d{2}(:\d{2})?\b'), blank);
    s = s.replaceAllMapped(RegExp(r'\d{1,2}(?:[,.]\d{1,2})?\s?%'), blank);
    s = s.replaceAllMapped(RegExp(r'\d{9,}'), blank);
    return s;
  }

  /// VAT rate printed in a row, e.g. `25%`, `25 %`, `Moms 12,00 %`.
  static VatRate? rate(String row) {
    final m = RegExp(r'(\d{1,2}(?:[,.]\d{1,2})?)\s?%').firstMatch(row);
    if (m == null) return null;
    return VatRate.parse(m.group(1)!);
  }

  /// All plausible dates in a row as ISO strings, in reading order.
  static List<String> dates(String row) {
    final found = <(int, String)>[];
    for (final m in RegExp(r'(?<!\d)(\d{4})[-./](\d{1,2})[-./](\d{1,2})(?!\d)').allMatches(row)) {
      final iso = _iso(m.group(1)!, m.group(2)!, m.group(3)!);
      if (iso != null) found.add((m.start, iso));
    }
    for (final m in RegExp(r'(?<!\d)(\d{1,2})[-./](\d{1,2})[-./](\d{4}|\d{2})(?!\d)').allMatches(row)) {
      var y = m.group(3)!;
      if (y.length == 2) y = '20$y';
      final iso = _iso(y, m.group(2)!, m.group(1)!);
      if (iso != null) found.add((m.start, iso));
    }
    for (final m in RegExp(r'(?<!\d)(20\d{2})(\d{2})(\d{2})(?!\d)').allMatches(row)) {
      final iso = _iso(m.group(1)!, m.group(2)!, m.group(3)!);
      if (iso != null) found.add((m.start, iso));
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    final out = <String>[];
    for (final f in found) {
      if (!out.contains(f.$2)) out.add(f.$2);
    }
    return out;
  }

  static String? _iso(String y, String m, String d) {
    final iso = '$y-${m.padLeft(2, '0')}-${d.padLeft(2, '0')}';
    final date = SwedishDates.parseIso(iso);
    if (date == null || date.year < 2000 || date.year > 2100) return null;
    return iso;
  }

  static bool containsAny(String normalized, Iterable<String> words) =>
      words.any((w) => normalized.contains(w));

  /// Levenshtein similarity in 0..1.
  static double similarity(String a, String b) {
    if (a == b) return 1;
    if (a.isEmpty || b.isEmpty) return 0;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    final maxLen = a.length > b.length ? a.length : b.length;
    return 1 - prev[b.length] / maxLen;
  }
}
