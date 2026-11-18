import 'dates.dart';
import 'document_parser.dart';
import 'models.dart';
import 'money.dart';
import 'ocr_models.dart';
import 'text_patterns.dart';
import 'vat.dart';

enum MatchKind { exact, remembered, possible, ignored, none }

/// One sales row found on the Z-report and how it relates to the user's
/// categories. Only [exact] and [remembered] matches are assigned
/// automatically; [possible] needs the user's confirmation.
class ZLine {
  /// Label of an amount whose name could not be read on the paper.
  static const unnamed = 'Rad utan namn';

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

/// What a Z-report says about payments (section "Betalmetoder"): card (with Swish) and
/// cash. Each is [Extracted.none] when the report does not say; when only one is found
/// the other is worked out from the day's sales. The till (växelkassa, given växel)
/// is not read.
class ZCash {
  final Extracted<Money> card;
  final Extracted<Money> cash;
  const ZCash({
    this.card = const Extracted.none(),
    this.cash = const Extracted.none(),
  });

  bool get isEmpty => !(card.hasValue || cash.hasValue);

  /// The words the reports use, in normalised form (lower case). Learned from the
  /// layouts of several registers, never from a customer's own papers.
  static const cardWords =
      r'kort|kortbetalning(?:ar)?|kortköp|kortförsäljning|bankkort|kontokort|betalkort|debetkort|kreditkort|visa|mastercard|amex|card|cards|credit card|debit card|card payment';
  static const swishWords = r'swish|swishbetalning(?:ar)?';
  static const cashWords =
      r'kontant försäljning|kontanter försäljning|kontant netto|kontanter netto|netto kontant|kontanter|kontant|kontantbetalning(?:ar)?|kontantförsäljning|betalt kontant|cash|cash payment';
  static const methodWords = r'betalmetod(?:er)?|betalsätt|betalningsmetod(?:er)?|betalningssätt|payment methods?';
  // Rows of the till (växelkassa, given växel) must never be taken for cash.
  static const tillWords =
      r'ingående|utgående|växel|given|kassabehållning|kassasaldo|insättning|uttag|utbetalning|kontanter in|kontant in|kontanter ut|kontant ut';

  static RegExp _label(String words) =>
      RegExp('^(?:summa |totalt |total )?(?:$words)(?![a-zåäö])');
  static final _card = _label(cardWords);
  static final _swish = _label(swishWords);
  static final _cash = _label(cashWords);
  static final _method = RegExp('^(?:$methodWords)(?![a-zåäö])');
  static final _till = RegExp('^(?:$tillWords)');

  /// Reads the figures from the rows of a report. [total] is the day's sales: it
  /// checks that card and cash add up and fills in whichever one is missing.
  static ZCash read(List<TextRow> rows, List<String> norm, Money? total) {
    // Prefer the "Betalmetoder" section; the cash section above it has other rows.
    var start = norm.indexWhere(_method.hasMatch);
    if (start < 0) start = 0;
    Extracted<Money> find(RegExp label) {
      for (var i = start; i < rows.length; i++) {
        if (!label.hasMatch(norm[i]) || _till.hasMatch(norm[i])) continue;
        final here = TextPatterns.amounts(rows[i].text).where((a) => a.hasDecimals).toList();
        if (here.isNotEmpty) return Extracted(here.last.value, Confidence.high, source: rows[i].text);
        if (i + 1 < rows.length) {
          final next = TextPatterns.amounts(rows[i + 1].text).where((a) => a.hasDecimals).toList();
          if (next.length == 1 && !RegExp(r'[a-zåäö]{3,}').hasMatch(norm[i + 1])) {
            return Extracted(next.single.value, Confidence.medium, source: '${rows[i].text} / ${rows[i + 1].text}');
          }
        }
      }
      return const Extracted.none();
    }

    var card = find(_card);
    final swish = find(_swish);
    var cash = find(_cash);
    if (swish.hasValue) {
      card = Extracted((card.value ?? Money.zero) + swish.value!,
          card.hasValue && card.confidence == Confidence.high && swish.confidence == Confidence.high ? Confidence.high : Confidence.medium,
          source: '${card.source ?? ''} ${swish.source ?? ''}'.trim(), note: 'Kort och Swish tillsammans');
    }
    // Card and cash should add up to the day's sales; when they do, both are sure.
    if (total != null && card.hasValue && cash.hasValue) {
      final fits = (card.value! + cash.value! - total).abs() < Money.ignoredDifference;
      if (fits) {
        card = Extracted(card.value, Confidence.high, source: card.source, note: card.note);
        cash = Extracted(cash.value, Confidence.high, source: cash.source);
      } else {
        card = Extracted(card.value, Confidence.medium, source: card.source, note: 'Kort och kontant stämmer inte med summan');
        cash = Extracted(cash.value, Confidence.medium, source: cash.source);
      }
    }
    // One found, the other follows from the day's sales (yellow, so it gets checked).
    if (total != null && card.hasValue && !cash.hasValue) {
      cash = Extracted(total - card.value!, Confidence.medium, note: 'Räknat: dagens summa minus kort');
    } else if (total != null && cash.hasValue && !card.hasValue) {
      card = Extracted(total - cash.value!, Confidence.medium, note: 'Räknat: dagens summa minus kontant');
    }
    return ZCash(card: card, cash: cash);
  }
}

class ZReportDraft {
  final Extracted<String> date;
  final List<String> otherDates;
  final Extracted<String> zNumber;
  final Extracted<Money> total;
  final List<ZLine> lines;
  final bool sectionFound;
  final List<String> notes;

  /// Payments and the till, when the report says.
  final ZCash cash;

  /// Names in the sales section with no amount beside them: a sign that the
  /// amount column is a line off.
  final int unlabelled;

  const ZReportDraft({
    this.unlabelled = 0,
    this.cash = const ZCash(),
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
  final Set<String> ignored;

  /// How many earlier Z-reports each category (by id) was on. Used to guess
  /// which category a nameless amount belongs to.
  final Map<int, int> usage;

  /// Used only to reject impossible future dates; defaults to now.
  final DateTime? today;
  const ZReportParser(this.categories,
      {this.aliases = const {}, this.ignored = const {}, this.usage = const {}, this.today});

  static const _sectionStart = [
    'försäljning per varugrupp', 'per varugrupp', 'varugrupper', 'varugrupp', 'artikelgrupper',
    'per artikelgrupp', 'avdelningar', 'per avdelning', 'kategorier', 'försäljning per kategori',
    // Other registers and English reports.
    'huvudgrupp', 'produktgrupp', 'product group', 'by category', 'per category', 'by department', 'departments',
  ];
  static const _sectionEnd = [
    'momsgrupp', 'per moms', 'moms', 'betalning', 'betalsätt', 'betalningsmedel', 'kvitton', 'kvitto',
    'grand total', 'kassalåda', 'växelkassa', 'bokföringsunderlag', 'returer', 'rabatter', 'personal',
    'per timme', 'per säljare', 'summa varugrupper', 'totalt varugrupper',
    'momssats', 'vat', 'betalmedel', 'betalningssätt', 'payment', 'tips', 'dricks', 'refund', 'discount',
    'summering', 'summary',
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
    'total sales': 100,
    'sales total': 95,
    'total turnover': 95,
    'gross sales': 90,
    'total omsättning': 90,
    'summa varugrupper': 80,
    'totalt varugrupper': 80,
    'totalt': 50,
    'summa': 40,
  };
  /// Company details and footer text that may sit next to amounts.
  static const _notSales = [
    'org nr', 'org.nr', 'orgnr', 'org. nr', 'organisationsnr', 'organisationsnummer', 'http', 'www', 'tel ',
    'telefon', 'momsreg', 'kvitto på köp', 'kvitto pa kop', 'kassa nr', 'kassanr', 'kassör', 'ej kvitto',
    '.com', '.se/', 'report',
    // Amounts that are not sales.
    'dricks', 'tips', 'växelkassa', 'change float', 'presentkort', 'gift card', 'kvittokopi', 'lådöppning',
  ];

  /// The web address and page number at the foot of a printed report.
  static bool _isFooter(String n) => _notSales.any(n.contains) || RegExp(r'\d\s*/\s*\d\s*$').hasMatch(n);

  static const _titleWords = ['z-rapport', 'z rapport', 'zrapport', 'z-report', 'z report', 'dagsrapport', 'kassarapport'];

  static const _printStamp = ['utskri', 'skriven', 'printed', 'kopia skapad'];

  static const _notTotal = ['grand total', 'ackumulerad', 'exkl', 'netto', 'moms', 'retur', 'rabatt', 'kontant', 'kort', 'swish', 'antal'];

  @override
  ZReportDraft parse(OcrResult ocr) => _withoutExtras(_bestReading(ocr));

  ZReportDraft _bestReading(OcrResult ocr) {
    final base = _parseRows(ocr.rows());
    if (_adds(base, base) && base.unlabelled == 0) return base;

    // On a curved page the amount column can be a line off, so try shifting
    // it. A shift is accepted only if the rows then add up to the total
    // exactly; being closer proves nothing and has given wrong amounts. The
    // total as read on its own row comes first.
    // A photo where the amount column sits higher than the names gives each
    // amount on the line above its name. That reading comes before the
    // shifts, so it wins a tie: a shift that moves every amount one name
    // down "adds up" just as well.
    final tries = [
      base,
      _parseRows(ocr.rows(), amountFirst: true),
      for (final s in ocr.rowShifts()) _parseRows(ocr.rows(rightShift: s)),
    ];
    for (final t in tries) {
      ZReportDraft? best;
      for (final l in tries) {
        if (!_adds(l, t) || l.lines.length < 2) continue;
        if (best == null || _doubts(l) < _doubts(best)) best = l;
      }
      if (best != null) {
        return ZReportDraft(
          date: base.date,
          otherDates: base.otherDates,
          zNumber: base.zNumber,
          total: t.total,
          lines: best.lines,
          sectionFound: best.sectionFound,
          notes: best == base
              ? base.notes
              : [...base.notes, 'Beloppen stod inte på samma rad som namnen och har parats ihop. Kontrollera mot pappret.'],
          // Card and cash from the reading where both were read and add up.
          cash: tries.map((r) => r.cash).firstWhere(
              (c) => c.card.confidence == Confidence.high && c.cash.confidence == Confidence.high,
              orElse: () => base.cash),
        );
      }
    }
    // Nothing adds up: show the rows as read, and the difference to the user.
    return base;
  }

  static int _doubts(ZReportDraft d) => d.unlabelled + d.lines.where((l) => l.label == ZLine.unnamed).length;

  /// How doubtful a reading is: names without amounts, amounts without names,
  /// and rows that do not add up to the total (or no total). Zero is a clean
  /// reading. Used to decide whether a slower second reading is worth doing.
  static int doubtsOf(ZReportDraft d) => _doubts(d) + (_adds(d, d) ? 0 : 1);

  static bool _adds(ZReportDraft lines, ZReportDraft total) {
    final diff = _difference(lines, total);
    return diff != null && diff < Money.ignoredDifference;
  }

  /// When the rows with a category already make up the day's total, a row
  /// that matches nothing can't be a sale.
  static ZReportDraft _withoutExtras(ZReportDraft d) {
    final total = d.total.value;
    final counted = d.lines.where((l) => l.categoryId != null);
    if (total == null || counted.isEmpty) return d;
    if ((Money.sum(counted.map((l) => l.amount)) - total).abs() >= Money.ignoredDifference) return d;
    return ZReportDraft(
      date: d.date,
      otherDates: d.otherDates,
      zNumber: d.zNumber,
      total: d.total,
      lines: d.lines.where((l) => l.match != MatchKind.none && l.label != ZLine.unnamed).toList(),
      sectionFound: d.sectionFound,
      notes: d.notes,
      cash: d.cash,
    );
  }

  /// An amount with no readable name: very short names are what OCR misses, so
  /// the category most often on earlier reports and not yet on this one is
  /// suggested (the shortest name when there is no history). The owner
  /// confirms it.
  ZLine _unnamedLine(Money amount, List<ZLine> lines) {
    final used = {for (final l in lines) l.categoryId ?? l.suggestedCategoryId};
    final free = categories.where((c) => c.active && c.id != null && !used.contains(c.id)).toList()
      ..sort((a, b) {
        // The category most often on earlier reports first; without history, the shortest name.
        final byUse = (usage[b.id] ?? 0).compareTo(usage[a.id] ?? 0);
        return byUse != 0 ? byUse : a.name.length.compareTo(b.name.length);
      });
    return ZLine(
      label: ZLine.unnamed,
      amount: amount,
      suggestedCategoryId: free.isEmpty ? null : free.first.id,
      match: MatchKind.possible,
      warning: 'Beloppet står på rapporten men namnet gick inte att läsa. Kontrollera mot pappret.',
    );
  }

  /// How far the rows of [lines] are from the total of [total], or null when
  /// either is missing.
  static Money? _difference(ZReportDraft lines, ZReportDraft total) {
    final t = total.total.value;
    if (t == null || lines.lines.isEmpty) return null;
    return (Money.sum(lines.lines.map((l) => l.amount)) - t).abs();
  }

  ZReportDraft _parseRows(List<TextRow> ocrRows, {bool amountFirst = false}) {
    final rows = [
      for (final r in _pairLabelsWithAmounts(ocrRows, amountFirst: amountFirst)) TextRow(_stripFooter(r.text), r.box, r.index)
    ];
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
    if (start < 0) {
      final i = norm.indexWhere((n) => _looksLikeSalesHeading(n));
      if (i >= 0 && !TextPatterns.amounts(rows[i].text).any((a) => a.hasDecimals)) start = i + 1;
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
    // Without a sales section, the sums for all time ("Grand total") and the
    // account list ("Bokföringsunderlag") below are never sales; nor is
    // anything after them.
    var stop = rows.length;
    if (start < 0) {
      final i = norm.indexWhere((n) =>
          RegExp(r'^gr[ao]n?d\s*total|momsgrupp').hasMatch(n) || (n.contains('underla') && !n.startsWith('underlag')));
      if (i >= 0) stop = i;
    }
    final range = start >= 0 ? [for (var i = start; i < end; i++) i] : [for (var i = 0; i < stop; i++) i];
    // When the sales amounts have öre, a whole number is not one of them: it
    // comes from other text, like "360" in the footer's onslip360.com.
    final found = [for (final i in range) ...TextPatterns.amounts(rows[i].text).reversed.take(1)];
    final decimalsOnly = found.where((a) => a.hasDecimals).length * 2 >= found.length;
    final hasLetters = RegExp(r'[A-Za-zÅÄÖåäö]{2,}');
    var unlabelled = 0;
    final nameless = <Money>[];
    for (final i in range) {
      final amounts = TextPatterns.amounts(rows[i].text);
      if (amounts.isEmpty) {
        if (start >= 0 && hasLetters.hasMatch(rows[i].text) && !_isFooter(norm[i])) unlabelled++;
        continue;
      }
      final amount = amounts.last;
      final label = _label(rows[i].text, amount.start);
      final nameLike = label.isNotEmpty && (hasLetters.hasMatch(label) || _looksLikeShortName(label));
      // In a sales section a misread "1 347." (grouped thousands) or "Drycka 40"
      // (a category's own name) is still an amount.
      final wholeIsSale = start >= 0 &&
          (!amount.plainDigits ||
              (nameLike && const {MatchKind.exact, MatchKind.remembered}.contains(_match(label, null).match)));
      if (decimalsOnly && !amount.hasDecimals && !wholeIsSale) continue;
      // Without a section: account rows ("150001 Försäljning Mat") and
      // negative amounts are not the day's sales.
      if (start < 0 && (amount.value.isNegative || RegExp(r'^\W?\w?\d{5,}\s').hasMatch(norm[i]))) continue;
      if (!nameLike) {
        // A row with a rate ("12%  714,29  85,71") is VAT, not a sale.
        if (start >= 0 && (amount.hasDecimals || wholeIsSale) && !amount.value.isZero && !rows[i].text.contains('%')) {
          nameless.add(amount.value);
        }
        continue;
      }
      if (_notSales.any((w) => norm[i].contains(w))) continue;
      final m = _match(label, TextPatterns.rate(rows[i].text));
      // Outside a category section only keep rows that look like a category.
      if (start < 0 && (m.match == MatchKind.none || m.match == MatchKind.ignored)) continue;
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
    // A name one letter off a category that is not on the report yet ("Vir" for
    // "Vin"): only suggested, the owner confirms. Skipped when more than one
    // category fits.
    final taken = {for (final l in lines) if (l.categoryId != null) l.categoryId};
    for (var k = 0; k < lines.length; k++) {
      final l = lines[k];
      if (l.match != MatchKind.none) continue;
      final near = _oneLetterOff(l.label, taken);
      if (near == null) continue;
      taken.add(near.id);
      lines[k] = ZLine(
        label: l.label,
        amount: l.amount,
        printedRate: l.printedRate,
        suggestedCategoryId: near.id,
        match: MatchKind.possible,
        warning: 'Liknar "${near.name}". Kontrollera mot pappret.',
      );
    }
    for (final a in nameless) {
      lines.add(_unnamedLine(a, lines));
    }
    if (start < 0) {
      notes.add('Ingen avdelning med försäljning per varugrupp hittades. Raderna matchades mot dina kategorier.');
    }

    // Total.
    Extracted<Money> total = const Extracted.none();
    var bestScore = 0;
    final candidates = <(int, Money, String)>[];
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
      // Misread: "Perioderns försåljning".
      // Also "Periodens försäljining".
      if (score < 100 && RegExp(r'^period\w* f\S*j\S*ng').hasMatch(n)) {
        score = 100;
        label = 'periodens försäljning';
      }
      // "Försäljningskvitton (49)": the sum of the day's sales receipts, also
      // misread ("Füradljningskvillon").
      final first = _fold(n.split(' ').first.replaceAll(RegExp(r'[^a-zåäöü]'), ''));
      if (score < 85 && TextPatterns.similarity(first, 'forsaljningskvitton') >= 0.7) {
        score = 85;
        label = 'försäljningskvitton';
      }
      if (label == null) continue;
      if (_notTotal.any((w) => n.contains(w)) && score < 90) continue;
      if (n.contains('grand total') || n.contains('ackumulerad') || n.contains('exkl')) continue;
      var amounts = TextPatterns.amounts(rows[i].text);
      if (amounts.isEmpty && i + 1 < rows.length && TextPatterns.amounts(rows[i + 1].text).length == 1) {
        amounts = TextPatterns.amounts(rows[i + 1].text);
      }
      if (amounts.isEmpty) continue;
      candidates.add((score, amounts.last.value, rows[i].text));
      if (score > bestScore) {
        bestScore = score;
        total = Extracted(amounts.last.value, score >= 90 ? Confidence.high : Confidence.medium,
            source: rows[i].text);
      }
    }
    // Registers word the total differently and may print it with and without
    // moms. The labelled total the sales rows add up to is the one.
    if (lines.isNotEmpty) {
      final rowSum = Money.sum(lines.map((l) => l.amount));
      final fits = candidates.where((c) => (c.$2 - rowSum).abs() < Money.ignoredDifference).toList()
        ..sort((a, b) => b.$1.compareTo(a.$1));
      if (fits.isNotEmpty) total = Extracted(fits.first.$2, Confidence.high, source: fits.first.$3);
    }
    // Card and cash payments together are also the day's sales.
    if (!total.hasValue) {
      Money? paidBy(RegExp word) {
        for (var i = 0; i < rows.length; i++) {
          final a = TextPatterns.amounts(rows[i].text);
          if (word.hasMatch(norm[i]) && a.isNotEmpty && a.last.hasDecimals) return a.last.value;
        }
        return null;
      }

      final card = paidBy(RegExp(r'^kort\b'));
      final cash = paidBy(RegExp(r'^kontanter?\b'));
      if (card != null && cash != null) {
        total = Extracted(card + cash, Confidence.medium, source: 'Kort + kontanter');
      }
    }
    if (!total.hasValue) notes.add('Dagsförsäljningen hittades inte. Fyll i den från rapporten.');

    // Business date: labelled dates first, never the phone's clock.
    // A period "Från … Till …": the business date is the "Från" date.
    // Print timestamps ("Utskriven …") are never the business date.
    final latest = (today ?? DateTime.now()).add(const Duration(days: 31));
    bool plausible(String iso) {
      final dt = SwedishDates.parseIso(iso);
      return dt != null && !dt.isAfter(latest) && dt.year >= 2000;
    }

    final dates = <String>[];
    String? labelled;
    String? labelledSrc;
    // The report belongs to the day it starts: the date after "Från"/"From".
    // "Till" is only when recording ended. A printed period is the fallback.
    String? from;
    String? fromSrc;
    String? periodStart;
    String? periodSrc;
    String? title;
    String? titleSrc;
    final titleRow = norm.indexWhere((n) => TextPatterns.containsAny(n, _titleWords));
    final hasPeriod = rows.any((r) => TextPatterns.dates(r.text).isNotEmpty && RegExp(r'\d\s*[-–]\s*\d{4}-').hasMatch(r.text));
    // "Tid: 2026-11-04 20:31" is when the report was printed.
    final printedAt = RegExp(r'\btid\s*:?\s*\d{4}-\d{2}-\d{2}', caseSensitive: false);
    for (var i = 0; i < rows.length; i++) {
      if (_printStamp.any((w) => norm[i].contains(w))) continue;
      // A bare date above the report title, or beside a printed period, is the
      // browser's print date in the page margin, never the business date.
      final bare = !RegExp(r'[a-zåäö]{2,}').hasMatch(norm[i]);
      if (bare && (i < titleRow || (hasPeriod && i <= titleRow + 2))) continue;
      var text = rows[i].text.replaceAll(printedAt, ' ');
      // The print time can stand before the title on the same line:
      // "2026-11-05 16:56   Z-Rapport (2026-11-04 00:00 - 2026-11-04 23:59)".
      if (i == titleRow) {
        final lower = text.toLowerCase();
        final at = [for (final w in _titleWords) lower.indexOf(w)].where((x) => x > 0).fold<int?>(null, (a, b) => a == null || b < a ? b : a);
        if (at != null) text = text.substring(at);
      }
      // A date far in the future is a misread, never a business date.
      final d = TextPatterns.dates(text).where(plausible).toList();
      // A period "2026-11-04 00:00 - 2026-11-04 23:59" starts on the sales day,
      // also when both ends fall on the same date.
      final period = RegExp(r'(\d{4}-\d{2}-\d{2})\s+\d{1,2}[:.]\d{2}\s*[-–]\s*\d{4}-\d{2}-\d{2}').firstMatch(text);
      if (periodStart == null && period != null && plausible(period[1]!)) {
        periodStart = period[1];
        periodSrc = rows[i].text;
      }
      dates.addAll(d);
      if (i == titleRow && d.isNotEmpty) {
        title = d.first;
        titleSrc = rows[i].text;
      }
      // A period "2026-10-30 06:00 – 2026-10-31 05:59": the first is Från.
      if (periodStart == null &&
          d.length >= 2 &&
          RegExp(r'(period|\s[-–]\s|\btill\b|\bto\b|\btom\b|t\.o\.m)').hasMatch(norm[i])) {
        periodStart = d.first;
        periodSrc = rows[i].text;
      }
      // Also misread: "Fran", "Fràn".
      // Also "Öppnad"/"Opened" for when the day was opened, and Norwegian "Fra".
      final fromIdx =
          // Not \b: it does not see å, ä and ö as letters.
          RegExp(r'(?<![a-zåäö])(fr[aåàáâä]n|fr\.?o\.?m\.?|from|fra|opened|öppnad(es)?)(?![a-zåäö])').firstMatch(norm[i]);
      if (from == null && fromIdx != null) {
        final after = TextPatterns.dates(rows[i].text.substring(fromIdx.start.clamp(0, rows[i].text.length)))
            .where(plausible)
            .toList();
        if (after.isNotEmpty) {
          from = after.first;
          fromSrc = rows[i].text;
        } else if (d.isEmpty && i + 1 < rows.length) {
          final next = TextPatterns.dates(rows[i + 1].text);
          if (next.isNotEmpty) {
            from = next.first;
            fromSrc = '${rows[i].text} / ${rows[i + 1].text}';
          }
        }
      }
      if (d.isNotEmpty &&
          labelled == null &&
          TextPatterns.containsAny(norm[i], ['affärsdag', 'bokföringsdag', 'försäljningsdag', 'datum', 'period', 'rapportdatum'])) {
        labelled = d.first;
        labelledSrc = rows[i].text;
      }
    }
    final unique = dates.toSet().toList();
    Extracted<String> date;
    if (from != null) {
      date = Extracted(from, Confidence.high, source: fromSrc, note: 'Från-datum i rapportens period');
    } else if (periodStart != null) {
      date = Extracted(periodStart, Confidence.high, source: periodSrc, note: 'Första dagen i rapportens period');
    } else if (title != null) {
      date = Extracted(title, unique.length == 1 ? Confidence.high : Confidence.medium, source: titleSrc);
    } else if (labelled != null) {
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
      unlabelled: unlabelled,
      cash: ZCash.read(rows, norm, total.value),
    );
  }

  /// When OCR reads the name column and the amount column separately, a name
  /// row ("Mat avhämtning") is followed by a row that is only an amount
  /// ("1 507,00"). Such pairs are joined. Headings are never joined.
  ///
  /// With [amountFirst] the amount column was read a line too high: an
  /// amount-only row ("5 105,00 kr") is joined with the name row below it
  /// ("Kort"), never with a heading or a total.
  static List<TextRow> _pairLabelsWithAmounts(List<TextRow> rows, {bool amountFirst = false}) {
    bool hasLetters(String s) => RegExp(r'[A-Za-zÅÄÖåäö]{2,}').hasMatch(s.replaceAll(RegExp(r'\b(kr|sek)\b', caseSensitive: false), ''));
    bool isHeading(String s) {
      final n = TextPatterns.normalize(s);
      // A heading like "Sales by VAT rate" ends the section wherever the word is.
      return _sectionStart.any(n.contains) ||
          _looksLikeSalesHeading(n) ||
          ZCash._method.hasMatch(n) ||
          _sectionEnd.any((w) => n.startsWith(w) || RegExp('(?<![a-zåäö])${RegExp.escape(w)}(?![a-zåäö])').hasMatch(n));
    }

    bool isName(String s) =>
        hasLetters(s) &&
        TextPatterns.amounts(s).isEmpty &&
        !isHeading(s) &&
        !_totalLabels.keys.any(TextPatterns.normalize(s).contains);

    final out = <TextRow>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final next = i + 1 < rows.length ? rows[i + 1] : null;
      if (amountFirst) {
        if (next != null && !hasLetters(r.text) && TextPatterns.amounts(r.text).isNotEmpty && isName(next.text)) {
          out.add(TextRow('${next.text}   ${r.text}', next.box, out.length));
          i++;
        } else {
          out.add(TextRow(r.text, r.box, out.length));
        }
        continue;
      }
      if (next != null &&
          hasLetters(r.text) &&
          TextPatterns.amounts(r.text).isEmpty &&
          !isHeading(r.text) &&
          !hasLetters(next.text) &&
          TextPatterns.amounts(next.text).isNotEmpty) {
        out.add(TextRow('${r.text}   ${next.text}', r.box, out.length));
        i++;
      } else {
        out.add(TextRow(r.text, r.box, out.length));
      }
    }
    return out;
  }

  /// A badly read "Försäljning per varugrupp" ("For sal jing pe varuiyr upp"):
  /// letters only, spaces dropped, compared with the heading. It must be
  /// nearer to it than to "Försäljning per momsgrupp", the VAT section.
  static bool _looksLikeSalesHeading(String n) {
    final c = _fold(n).replaceAll(RegExp(r'[^a-z]'), '');
    if (c.length < 15) return false;
    double near(String target) {
      var best = 0.0;
      for (var len = target.length - 2; len <= target.length + 2; len++) {
        final s = TextPatterns.similarity(c.substring(0, len.clamp(0, c.length)), target);
        if (s > best) best = s;
      }
      return best;
    }

    final sales = near('forsaljningpervarugrupp');
    return sales >= 0.7 && sales > near('forsaljningpermomsgrupp');
  }

  /// Web addresses and page numbers from the foot of the page, cut out of a
  /// row. The row itself is never dropped for them: "öl   2 988,00 kr   https://x.com/report"
  /// is still the row for öl.
  static String _stripFooter(String s) => s
      .replaceAll(RegExp(r'(https?://|www\.)\S*', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\S+\.(com|se|no|net|org|nu|dk|fi)\b\S*', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'(?<![\d,.])\d{1,3}\s*/\s*(?:\d{1,3})?\s*$'), ' ')
      .replaceAll(RegExp(r'\s{2,}'), '   ')
      .trim();

  /// OCR swaps look-alike characters and drops dots, most often in short
  /// words ("0l" or "ol" for "öl"). Used only to compare a name with the owner's categories and rules.
  static String _fold(String n) => n
      .replaceAll('0', 'o')
      .replaceAll('1', 'l')
      .replaceAll('5', 's')
      .replaceAll('8', 'b')
      .replaceAll('ö', 'o')
      .replaceAll('ä', 'a')
      .replaceAll('å', 'a');

  /// The one active category not yet on the report whose name is one letter
  /// away from [label] (OCR mixes up letters like n and r). Null when none or
  /// several fit, or the name is shorter than three letters.
  Category? _oneLetterOff(String label, Set<int?> taken) {
    final f = _fold(normalizeLabel(label));
    if (f.length < 3) return null;
    final close = categories.where((c) {
      if (!c.active || c.id == null || taken.contains(c.id)) return false;
      final g = _fold(normalizeLabel(c.name));
      if (g.length < 3) return false;
      final longest = f.length > g.length ? f.length : g.length;
      return ((1 - TextPatterns.similarity(f, g)) * longest).round() <= 1;
    }).toList();
    return close.length == 1 ? close.single : null;
  }

  /// A very short name that has only one real letter because OCR read a digit
  /// for the other. It counts as a name only when it matches something of the
  /// owner's once look-alike characters are folded.
  bool _looksLikeShortName(String label) =>
      label.length <= 5 && RegExp(r'[A-Za-zÅÄÖåäö]').hasMatch(label) && _match(label, null).match != MatchKind.none;

  /// Text before the amount, without quantities, percentages and codes.
  static String _label(String row, int amountStart) {
    var s = row.substring(0, amountStart);
    s = s.replaceAll(RegExp(r'\d{1,2}(?:[,.]\d{1,2})?\s?%'), ' ');
    s = s.replaceAll(RegExp(r'(?<![A-Za-zÅÄÖåäö])\d+(?:[,.]\d+)?(?![A-Za-zÅÄÖåäö])'), ' ');
    s = s.replaceAll(RegExp(r'\b(st|kr|sek|x)\b', caseSensitive: false), ' ');
    s = s.replaceAll(RegExp(r'[:.;*#=]+'), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String normalizeLabel(String s) => TextPatterns.normalize(s);

  ({int? categoryId, int? suggested, MatchKind match, String? warning}) _match(String label, VatRate? printed) {
    final n = normalizeLabel(label);
    final active = categories.where((c) => c.active && c.id != null).toList();
    // Rules may be stored in any case ("Öl" or "öl"); compare them the same way.
    final aliases = {for (final e in this.aliases.entries) normalizeLabel(e.key): e.value};
    final ignored = {for (final l in this.ignored) normalizeLabel(l)};

    String? rateWarning(Category c) => printed != null && printed != c.vat
        ? 'Rapporten visar ${printed.label} men ${c.name} har ${c.vat.label}.'
        : null;

    // The owner's own rules ("Fält på Z-rapport") come first.
    if (ignored.contains(n)) {
      return (categoryId: null, suggested: null, match: MatchKind.ignored, warning: null);
    }
    final alias = aliases[n];
    if (alias != null && active.any((c) => c.id == alias)) {
      final c = active.firstWhere((c) => c.id == alias);
      final w = rateWarning(c);
      return w == null
          ? (categoryId: alias, suggested: null, match: MatchKind.remembered, warning: null)
          : (categoryId: null, suggested: alias, match: MatchKind.possible, warning: w);
    }
    for (final c in active) {
      if (normalizeLabel(c.name) == n) {
        final w = rateWarning(c);
        return w == null
            ? (categoryId: c.id, suggested: null, match: MatchKind.exact, warning: null)
            : (categoryId: null, suggested: c.id, match: MatchKind.possible, warning: w);
      }
    }
    // The same name read with look-alike characters ("0l" for "öl"): only
    // suggested, the owner confirms.
    final folded = _fold(n);
    {
      for (final e in aliases.entries) {
        final c = active.where((c) => c.id == e.value).firstOrNull;
        if (c != null && _fold(e.key) == folded) {
          return (categoryId: null, suggested: c.id, match: MatchKind.possible, warning: rateWarning(c));
        }
      }
      for (final c in active) {
        if (_fold(normalizeLabel(c.name)) == folded) {
          return (categoryId: null, suggested: c.id, match: MatchKind.possible, warning: rateWarning(c));
        }
      }
    }
    // A line one letter off the owner's own rule ("avhäntning") counts as that
    // rule, as the owner decided; a line further off is only suggested.
    String? closest;
    var closestScore = 0.0;
    for (final key in aliases.keys) {
      final s = TextPatterns.similarity(n, key);
      if (s > closestScore) {
        closestScore = s;
        closest = key;
      }
    }
    if (closest != null && closestScore >= 0.8) {
      final id = aliases[closest]!;
      final c = active.where((c) => c.id == id).firstOrNull;
      final oneLetterOff = closest.length >= 5 && (1 - closestScore) * closest.length <= 1.01;
      if (c != null && oneLetterOff && rateWarning(c) == null) {
        return (categoryId: id, suggested: null, match: MatchKind.remembered, warning: null);
      }
      if (c != null) {
        return (categoryId: null, suggested: id, match: MatchKind.possible, warning: 'Liknar "$closest" som räknas som ${c.name}.');
      }
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
    final re = RegExp(
        r'(?:z[-\s]?(?:nr|nummer|rapport\s*(?:nr|nummer)?)|rapport\s*nr|rapportnummer|löpnummer|l[øo]penummer|sequence\s*number|report\s*number)\s*[:.#]?\s*(\d{1,8})',
        caseSensitive: false);
    for (var i = 0; i < rows.length; i++) {
      final m = re.firstMatch(rows[i].text);
      // "Z-RAPPORT 2026-11 -17 11:16": a date, not the report number.
      if (m != null && RegExp(r'^\s*[-./]\s*\d{1,2}\s*[-./]').hasMatch(rows[i].text.substring(m.end))) continue;
      if (m != null) return Extracted(m.group(1)!, Confidence.medium, source: rows[i].text);
    }
    // "Underlag: Z1-180"
    final underlag = RegExp(r'underlag\s*[:.]?\s*([a-z]{0,2}\d[\w-]*)', caseSensitive: false);
    for (final r in rows) {
      final m = underlag.firstMatch(r.text);
      if (m != null) return Extracted(m.group(1)!, Confidence.high, source: r.text);
    }
    return const Extracted.none();
  }
}

