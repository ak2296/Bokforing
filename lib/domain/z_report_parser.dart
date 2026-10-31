import 'document_parser.dart';
import 'models.dart';
import 'money.dart';
import 'ocr_models.dart';
import 'text_patterns.dart';
import 'vat.dart';

enum MatchKind { exact, remembered, possible, none }

/// One sales row found on the Z-report and how it relates to the user's
/// categories. Only [exact] and [remembered] matches are assigned
/// automatically; [possible] needs the user's confirmation.
class ZLine {
  final String label;
  final Money amount;
  final VatRate? printedRate;
  final int? categoryId;
  final int? suggestedCategoryId;
  final MatchKind match;
  final String? warning;

  const ZLine({
    required this.label,
    required this.amount,
    this.printedRate,
    this.categoryId,
    this.suggestedCategoryId,
    required this.match,
    this.warning,
  });
}

class ZReportDraft {
  final Extracted<String> date;
  final List<String> otherDates;
  final Extracted<String> zNumber;
  final Extracted<Money> total;
  final List<ZLine> lines;
  final bool sectionFound;
  final List<String> notes;

  const ZReportDraft({
    required this.date,
    required this.otherDates,
    required this.zNumber,
    required this.total,
    required this.lines,
    required this.sectionFound,
    required this.notes,
  });

  /// Sum of the rows assigned to a category, with optional user overrides
  /// (row index -> category id, or null to ignore the row).
  Money sumWith(Map<int, int?> overrides) {
    var sum = Money.zero;
    for (var i = 0; i < lines.length; i++) {
      final id = overrides.containsKey(i) ? overrides[i] : lines[i].categoryId;
      if (id != null) sum += lines[i].amount;
    }
    return sum;
  }
}

/// Generic Z-report reader. Layouts differ between cash registers, so it
/// looks for a per-category section when there is one and otherwise matches
/// rows against the user's own categories.
class ZReportParser implements DocumentParser<ZReportDraft> {
  final List<Category> categories;
  final Map<String, int> aliases;
  const ZReportParser(this.categories, {this.aliases = const {}});

  static const _sectionStart = [
    'försäljning per varugrupp', 'per varugrupp', 'varugrupper', 'varugrupp', 'artikelgrupper',
    'per artikelgrupp', 'avdelningar', 'per avdelning', 'kategorier', 'försäljning per kategori',
  ];
  static const _sectionEnd = [
    'momsgrupp', 'per moms', 'moms', 'betalning', 'betalsätt', 'betalningsmedel', 'kvitton', 'kvitto',
    'grand total', 'kassalåda', 'växelkassa', 'bokföringsunderlag', 'returer', 'rabatter', 'personal',
    'per timme', 'per säljare', 'summa varugrupper', 'totalt varugrupper',
  ];
  static const _totalLabels = <String, int>{
    'total försäljning': 100,
    'totalförsäljning': 100,
    'periodens försäljning': 100,
    'dagens försäljning': 100,
    'försäljning totalt': 95,
    'summa försäljning': 95,
    'försäljning inkl': 95,
    'bruttoförsäljning': 90,
    'summa varugrupper': 80,
    'totalt varugrupper': 80,
    'totalt': 50,
    'summa': 40,
  };
  static const _notTotal = ['grand total', 'ackumulerad', 'exkl', 'netto', 'moms', 'retur', 'rabatt', 'kontant', 'kort', 'swish', 'antal'];

  @override
  ZReportDraft parse(OcrResult ocr) {
    final rows = ocr.rows();
    final norm = [for (final r in rows) TextPatterns.normalize(r.text)];
    final notes = <String>[];

    // Category section.
    var start = -1;
    for (var i = 0; i < rows.length; i++) {
      if (_sectionStart.any((s) => norm[i].contains(s)) && TextPatterns.amounts(rows[i].text).isEmpty) {
        start = i + 1;
        break;
      }
    }
    var end = rows.length;
    if (start >= 0) {
      for (var i = start; i < rows.length; i++) {
        final isHeading = TextPatterns.amounts(rows[i].text).isEmpty && _sectionEnd.any((s) => norm[i].contains(s));
        final isSectionTotal = _totalLabels.entries.any((e) => e.value >= 80 && norm[i].contains(e.key));
        if (isHeading || isSectionTotal || (_sectionEnd.any((s) => norm[i].startsWith(s)))) {
          end = i;
          break;
        }
      }
    }

    final lines = <ZLine>[];
    final range = start >= 0 ? [for (var i = start; i < end; i++) i] : [for (var i = 0; i < rows.length; i++) i];
    for (final i in range) {
      final amounts = TextPatterns.amounts(rows[i].text);
      if (amounts.isEmpty) continue;
      final amount = amounts.last;
      final label = _label(rows[i].text, amount.start);
      if (label.isEmpty) continue;
      final m = _match(label, TextPatterns.rate(rows[i].text));
      // Outside a category section only keep rows that look like a category.
      if (start < 0 && m.match == MatchKind.none) continue;
      if (start < 0 && _notTotal.any((w) => norm[i].contains(w))) continue;
      lines.add(ZLine(
        label: label,
        amount: amount.value,
        printedRate: TextPatterns.rate(rows[i].text),
        categoryId: m.categoryId,
        suggestedCategoryId: m.suggested,
        match: m.match,
        warning: m.warning,
      ));
    }
    if (start < 0) {
      notes.add('Ingen avdelning med försäljning per varugrupp hittades. Raderna matchades mot dina kategorier.');
    }

    // Total.
    Extracted<Money> total = const Extracted.none();
    var bestScore = 0;
    for (var i = 0; i < rows.length; i++) {
      if (i >= start && i < end && start >= 0) continue;
      final n = norm[i];
      var score = 0;
      String? label;
      for (final e in _totalLabels.entries) {
        if (n.contains(e.key) && e.value > score) {
          score = e.value;
          label = e.key;
        }
      }
      if (label == null) continue;
      if (_notTotal.any((w) => n.contains(w)) && score < 90) continue;
      if (n.contains('grand total') || n.contains('ackumulerad')) continue;
      var amounts = TextPatterns.amounts(rows[i].text);
      if (amounts.isEmpty && i + 1 < rows.length && TextPatterns.amounts(rows[i + 1].text).length == 1) {
        amounts = TextPatterns.amounts(rows[i + 1].text);
      }
      if (amounts.isEmpty) continue;
      if (score > bestScore) {
        bestScore = score;
        total = Extracted(amounts.last.value, score >= 90 ? Confidence.high : Confidence.medium,
            source: rows[i].text);
      }
    }
    if (!total.hasValue) notes.add('Dagsförsäljningen hittades inte. Fyll i den från rapporten.');

    // Business date: labelled dates first, never the phone's clock.
    final dates = <String>[];
    String? labelled;
    String? labelledSrc;
    for (var i = 0; i < rows.length; i++) {
      final d = TextPatterns.dates(rows[i].text);
      dates.addAll(d);
      if (d.isNotEmpty &&
          labelled == null &&
          TextPatterns.containsAny(norm[i], ['affärsdag', 'bokföringsdag', 'försäljningsdag', 'datum', 'period', 'rapportdatum'])) {
        labelled = d.first;
        labelledSrc = rows[i].text;
      }
    }
    final unique = dates.toSet().toList();
    Extracted<String> date;
    if (labelled != null) {
      date = Extracted(labelled, unique.length == 1 ? Confidence.high : Confidence.medium, source: labelledSrc);
    } else if (unique.length == 1) {
      date = Extracted(unique.single, Confidence.medium);
    } else if (unique.isNotEmpty) {
      date = Extracted(unique.first, Confidence.low, note: 'Flera datum hittades. Kontrollera vilket som är försäljningsdagen.');
    } else {
      date = const Extracted.none();
      notes.add('Inget datum hittades. Fyll i försäljningsdagen.');
    }

    return ZReportDraft(
      date: date,
      otherDates: unique.where((d) => d != date.value).toList(),
      zNumber: _zNumber(rows, norm),
      total: total,
      lines: lines,
      sectionFound: start >= 0,
      notes: notes,
    );
  }

  /// Text before the amount, without quantities, percentages and codes.
  static String _label(String row, int amountStart) {
    var s = row.substring(0, amountStart);
    s = s.replaceAll(RegExp(r'\d{1,2}(?:[,.]\d{1,2})?\s?%'), ' ');
    s = s.replaceAll(RegExp(r'(?<![A-Za-zÅÄÖåäö])\d+(?:[,.]\d+)?(?![A-Za-zÅÄÖåäö])'), ' ');
    s = s.replaceAll(RegExp(r'\b(st|kr|sek|x)\b', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'[:.;*#=]+'), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String normalizeLabel(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  ({int? categoryId, int? suggested, MatchKind match, String? warning}) _match(String label, VatRate? printed) {
    final n = normalizeLabel(label);
    final active = categories.where((c) => c.active && c.id != null).toList();

    String? rateWarning(Category c) => printed != null && printed != c.vat
        ? 'Rapporten visar ${printed.label} men ${c.name} har ${c.vat.label}.'
        : null;

    for (final c in active) {
      if (normalizeLabel(c.name) == n) {
        final w = rateWarning(c);
        return w == null
            ? (categoryId: c.id, suggested: null, match: MatchKind.exact, warning: null)
            : (categoryId: null, suggested: c.id, match: MatchKind.possible, warning: w);
      }
    }
    final alias = aliases[n];
    if (alias != null && active.any((c) => c.id == alias)) {
      final c = active.firstWhere((c) => c.id == alias);
      final w = rateWarning(c);
      return w == null
          ? (categoryId: alias, suggested: null, match: MatchKind.remembered, warning: null)
          : (categoryId: null, suggested: alias, match: MatchKind.possible, warning: w);
    }
    // Possible matches: a category name as a whole word, or close spelling.
    Category? best;
    var bestScore = 0.0;
    for (final c in active) {
      final cn = normalizeLabel(c.name);
      var score = TextPatterns.similarity(n, cn);
      final words = n.split(' ');
      if (words.contains(cn) || cn.split(' ').every(words.contains)) score = score < 0.75 ? 0.75 : score;
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    if (best != null && bestScore >= 0.75) {
      return (categoryId: null, suggested: best.id, match: MatchKind.possible, warning: rateWarning(best));
    }
    return (categoryId: null, suggested: null, match: MatchKind.none, warning: null);
  }

  Extracted<String> _zNumber(List<TextRow> rows, List<String> norm) {
    final re = RegExp(r'(?:z[-\s]?(?:nr|nummer|rapport\s*(?:nr|nummer)?)|rapport\s*nr|löpnummer)\s*[:.#]?\s*(\d{1,8})',
        caseSensitive: false);
    for (var i = 0; i < rows.length; i++) {
      final m = re.firstMatch(rows[i].text);
      if (m != null) return Extracted(m.group(1)!, Confidence.medium, source: rows[i].text);
    }
    return const Extracted.none();
  }
}

