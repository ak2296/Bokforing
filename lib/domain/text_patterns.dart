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

  /// Printed as digits only, with no comma, dot or space: "5850".
  final bool plainDigits;
  const AmountToken(this.value, this.start, this.end, this.hasDecimals, {this.plainDigits = false});
}

class TextPatterns {
  const TextPatterns._();

  /// Lowercase, collapse spaces, fold common OCR confusions in words.
  static String normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  // Grouped thousands with decimals, plain decimals, `125:-`, plain integers.
  static final _amount = RegExp(
      r'(?<![\d.,])-?(?:\d{1,3}(?:[  .,]\d{3})+(?:[,.]\d{1,2})?|\d+[,.]\d{1,2}|\d+:-|\d+)(?:-)?(?![\d%])');

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
      out.add(AmountToken(v, m.start, m.end, hasDecimals, plainDigits: RegExp(r'^\d+$').hasMatch(raw)));
    }
    return out;
  }

  /// Replaces dates, percentages, times and long digit runs with spaces so
  /// they are never read as amounts.
  static String _maskNonAmounts(String row) {
    var s = row;
    String blank(Match m) => ' ' * m.group(0)!.length;
    // Bankgiro "439-9093", org number "556628-9285", phone "040-185310".
    s = s.replaceAllMapped(RegExp(r'(?<![\d-])\d{3,4}-\d{4}(?![\d-])'), blank);
    s = s.replaceAllMapped(RegExp(r'(?<![\d-])\d{6}-\d{4}(?![\d-])'), blank);
    s = s.replaceAllMapped(RegExp(r'(?<![\d-])0\d{1,3}-\d(?: ?\d){4,8}(?![\d-])'), blank);
    s = s.replaceAllMapped(RegExp(r'(?<!\d)20\d{2} \d{2} \d{2}(?!\d)'), blank);
    s = s.replaceAllMapped(RegExp(r'\d{4}[-./]\d{1,2}[-./]\d{1,2}'), blank);
    s = s.replaceAllMapped(RegExp(r'\b\d{1,2}[-./]\d{1,2}[-./]\d{2,4}\b'), blank);
    s = s.replaceAllMapped(RegExp(r'\b\d{1,2}[./]\d{1,2},\d{4}\b'), blank);
    s = s.replaceAllMapped(RegExp(r'(\d{1,2})\.?\s+([A-Za-zåäÅÄ]{3,9})\.?,?\s+\d{4}'),
        (m) => _month(m.group(2)!) == null ? m.group(0)! : blank(m));
    s = s.replaceAllMapped(RegExp(r'\b([A-Za-zåäÅÄ]{3,9})\.?\s+\d{1,2},?\s+\d{4}'),
        (m) => _month(m.group(1)!) == null ? m.group(0)! : blank(m));
    s = s.replaceAllMapped(RegExp(r'\b\d{1,2}:\d{2}(:\d{2})?\b'), blank);
    s = s.replaceAllMapped(RegExp(r'\d{1,2}(?:[,.]\d{1,2})?\s?%'), blank);
    // A page number: "1/2".
    s = s.replaceAllMapped(RegExp(r'(?<![\d.,/])\d{1,3}/\d{1,3}(?![\d/])'), blank);
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
    // Day first with a full year; a misread comma is accepted ("24.09,2026").
    for (final m in RegExp(r'(?<!\d)(\d{1,2})[-./,](\d{1,2})[-./,](\d{4})(?!\d)').allMatches(row)) {
      final iso = _iso(m.group(3)!, m.group(2)!, m.group(1)!);
      if (iso != null) found.add((m.start, iso));
    }
    // Spaces instead of dashes on a giro slip: "2026 10 28".
    for (final m in RegExp(r'(?<!\d)(20\d{2}) (\d{2}) (\d{2})(?!\d)').allMatches(row)) {
      final iso = _iso(m.group(1)!, m.group(2)!, m.group(3)!);
      if (iso != null) found.add((m.start, iso));
    }
    for (final m in _short.allMatches(row)) {
      final iso = _shortDate(m.group(1)!, m.group(2)!, m.group(3)!);
      if (iso != null) found.add((m.start, iso));
    }
    // Month names, Swedish and English: "28 okt 2026", "28 October 2026",
    // "Oct 28, 2026".
    for (final m in RegExp(r'(?<!\d)(\d{1,2})\.?\s+([A-Za-zåäÅÄ]{3,9})\.?,?\s+(\d{4})(?!\d)').allMatches(row)) {
      final mo = _month(m.group(2)!);
      final iso = mo == null ? null : _iso(m.group(3)!, '$mo', m.group(1)!);
      if (iso != null) found.add((m.start, iso));
    }
    for (final m in RegExp(r'\b([A-Za-zåäÅÄ]{3,9})\.?\s+(\d{1,2}),?\s+(\d{4})(?!\d)').allMatches(row)) {
      final mo = _month(m.group(1)!);
      final iso = mo == null ? null : _iso(m.group(3)!, '$mo', m.group(2)!);
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

  static final _short = RegExp(r'(?<!\d)(\d{1,2})[-./](\d{1,2})[-./](\d{2})(?!\d)');

  /// A two-digit year can be first or last: "26.10.24" and "09/10/26". Only
  /// realistic years count; 2007 or 2031 is not one.
  static List<String> _shortReadings(String a, String month, String c) {
    final latest = DateTime.now().year + 1;
    String? read(String yy, String dd) {
      final year = 2000 + int.parse(yy);
      return year >= 2015 && year <= latest ? _iso('$year', month, dd) : null;
    }

    return {read(c, a), read(a, c)}.whereType<String>().toList();
  }

  static int _daysFromToday(String iso) =>
      SwedishDates.parseIso(iso)!.difference(DateTime.now()).inDays.abs();

  /// The reading closest to today wins: a paper is scanned soon after it is
  /// printed.
  static String? _shortDate(String a, String month, String c) {
    final readings = _shortReadings(a, month, c);
    if (readings.isEmpty) return null;
    readings.sort((x, y) => _daysFromToday(x).compareTo(_daysFromToday(y)));
    return readings.first;
  }

  /// True when a short date in [row] has two readings that are both recent,
  /// so the closest one may still be the wrong one.
  static bool hasAmbiguousDate(String row) => _short.allMatches(row).any((m) {
        final readings = _shortReadings(m.group(1)!, m.group(2)!, m.group(3)!);
        return readings.length == 2 && readings.every((r) => _daysFromToday(r) <= 400);
      });

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'maj': 5, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'okt': 10, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Month number from a Swedish or English month name or abbreviation.
  static int? _month(String word) {
    final w = word.toLowerCase();
    if (w.length < 3) return null;
    final m = _months[w.substring(0, 3)];
    if (m == null) return null;
    const full = [
      'januari', 'january', 'februari', 'february', 'mars', 'march', 'april', 'maj', 'may', 'juni', 'june',
      'juli', 'july', 'augusti', 'august', 'september', 'oktober', 'october', 'november', 'december', 'sept',
    ];
    // Accept a 3-letter abbreviation or a full month name, nothing else.
    return w.length == 3 || full.contains(w) ? m : null;
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
