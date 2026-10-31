import 'dates.dart';
import 'document_parser.dart';
import 'invoice_prefs.dart';
import 'models.dart';
import 'money.dart';
import 'ocr_models.dart';
import 'text_patterns.dart';
import 'validation.dart';
import 'vat.dart';

/// A ranked candidate for the invoice total, kept so the review screen can
/// offer alternatives.
class TotalCandidate {
  final Money value;
  final double score;
  final String row;
  final List<String> reasons;
  const TotalCandidate(this.value, this.score, this.row, this.reasons);
}

class InvoiceDraft {
  final Extracted<String> date;
  final Extracted<String> dueDate;
  final Extracted<String> supplier;
  final Extracted<String> invoiceNumber;
  final Extracted<String> ocrReference;
  final Extracted<Money> total;
  final Extracted<Money> vatTotal;
  final bool vatCalculated;
  final List<InvoiceVatLine> vatLines;
  final Money? net;
  final List<TotalCandidate> totalCandidates;
  final List<String> notes;

  /// True for a kreditnota: amounts are negative and are subtracted.
  final bool isCredit;

  /// Every labelled date found, so the user can pick another one.
  final List<({String label, String date})> dateOptions;

  const InvoiceDraft({
    this.isCredit = false,
    this.dateOptions = const [],
    required this.date,
    required this.dueDate,
    required this.supplier,
    required this.invoiceNumber,
    required this.ocrReference,
    required this.total,
    required this.vatTotal,
    required this.vatCalculated,
    required this.vatLines,
    required this.net,
    required this.totalCandidates,
    required this.notes,
  });
}


/// Generic invoice/receipt reader. It ranks every labelled amount instead of
/// taking the largest number, and separates totals from cash tendered,
/// change, net amounts, subtotals and discounts.
class InvoiceParser implements DocumentParser<InvoiceDraft> {
  final InvoicePrefs prefs;
  const InvoiceParser({this.prefs = const InvoicePrefs()});

  /// Printed label -> (score, group in [InvoicePrefs.totalLabelOptions]).
  static const _totalLabels = <String, (double, String)>{
    'summa att betala': (100, 'att betala'),
    'belopp att betala': (100, 'att betala'),
    'totalt att betala': (100, 'att betala'),
    'att betala': (95, 'att betala'),
    'att erhålla': (40, 'att betala'),
    'fakturabelopp': (90, 'fakturabelopp'),
    'betalt belopp': (85, 'betalt belopp'),
    'belopp betalt': (85, 'betalt belopp'),
    'totalbelopp': (85, 'totalt'),
    'totalt inkl': (90, 'totalt'),
    'totalt': (80, 'totalt'),
    'total': (70, 'totalt'),
    'bruttobelopp': (80, 'brutto'),
    'brutto': (75, 'brutto'),
    'summa inkl': (90, 'summa'),
    'summa': (60, 'summa'),
  };

  static const _creditWords = ['kreditnota', 'kreditfaktura', 'kredit faktura', 'credit note', 'kreditering'];

  /// Rows with these words are never the invoice total.
  static const _neverTotal = [
    'kvar att betala', 'tidigare betalt', 'redan betalt', 'delsumma', 'subtotal', 'mellansumma',
    'rabatt', 'öresavrundning', 'öresutj', 'avrundning', 'växel', 'tillbaka', 'saldo', 'bonus', 'poäng', 'antal',
  ];

  /// Net amounts and VAT rows, unless the row also says the amount includes
  /// VAT or is the amount to pay.
  static const _notTotalUnlessInclusive = [
    'exkl', 'exklusive', 'netto', 'momspl', 'varav moms', 'momsbelopp', 'moms',
  ];

  static bool _excludedFromTotal(String n) {
    if (_neverTotal.any((w) => n.contains(w))) return true;
    final inclusive = n.contains('att betala') || n.contains('inkl');
    return !inclusive && _notTotalUnlessInclusive.any((w) => n.contains(w));
  }

  static const _cashReceived = ['kontant', 'mottaget', 'erhållet', 'erhållit', 'betalt kontant', 'lämnat'];
  static const _change = ['växel', 'tillbaka', 'åter'];
  static const _cardPaid = ['kontokort', 'kort', 'betalt med', 'swish', 'kortbetalning', 'bankkort'];

  @override
  InvoiceDraft parse(OcrResult ocr) {
    final rows = ocr.rows();
    final norm = [for (final r in rows) TextPatterns.normalize(r.text)];
    final notes = <String>[];
    final isCredit = norm.any((n) => _creditWords.any((w) => n.contains(w)));

    final vat = _vat(rows, norm);
    final payment = _payment(rows, norm);
    final candidates = _totalCandidates(rows, norm, vat, payment, allowNegative: isCredit);
    Extracted<Money> total = const Extracted.none();
    if (candidates.isNotEmpty) {
      final best = candidates.first;
      final second = candidates.length > 1 ? candidates[1] : null;
      final clearWinner = second == null || second.value == best.value || best.score - second.score >= 25;
      final supported = best.reasons.any((r) => r.startsWith('stämmer'));
      final conf = best.score >= 90 && (clearWinner || supported)
          ? Confidence.high
          : best.score >= 60
              ? Confidence.medium
              : Confidence.low;
      total = Extracted(best.value, conf, source: best.row, note: best.reasons.join(', '));
    } else {
      notes.add('Ingen rad med "Att betala", "Totalt" eller "Summa" hittades. Fyll i summan själv.');
    }

    // VAT total: explicit total, otherwise sum of the rate lines, otherwise
    // reconstructed from an explicitly printed net amount.
    var vatCalculated = false;
    Extracted<Money> vatTotal = const Extracted.none();
    if (vat.explicitTotal != null) {
      vatTotal = Extracted(vat.explicitTotal!.$1, Confidence.high, source: vat.explicitTotal!.$2);
    } else if (vat.lines.isNotEmpty) {
      vatTotal = Extracted(Money.sum(vat.lines.map((l) => l.vat)), vat.fromTable ? Confidence.high : Confidence.medium,
          source: 'Summa av moms per momssats');
    } else if (vat.net != null && total.value != null && total.value! > vat.net!) {
      final v = total.value! - vat.net!;
      if (const AccountingValidationEngine().checkVatPlausible(v, total.value!) == null) {
        vatTotal = Extracted(v, Confidence.medium, note: 'Beräknad: summa minus netto');
        vatCalculated = true;
      }
    }
    if (!vatTotal.hasValue) notes.add('Ingen moms hittades på dokumentet. Kontrollera om momsen saknas eller fyll i den.');

    // A kreditnota reduces expenses: total, VAT and VAT lines become negative
    // whether or not the minus sign was printed.
    var vatLines = vat.lines;
    if (isCredit) {
      Money neg(Money m) => -m.abs();
      if (total.value != null) {
        total = Extracted(neg(total.value!), total.confidence, source: total.source, note: total.note);
      }
      if (vatTotal.value != null) {
        vatTotal = Extracted(neg(vatTotal.value!), vatTotal.confidence, source: vatTotal.source, note: vatTotal.note);
      }
      vatLines = [
        for (final l in vat.lines)
          InvoiceVatLine(
            rate: l.rate,
            vat: neg(l.vat),
            net: l.net == null ? null : neg(l.net!),
            gross: l.gross == null ? null : neg(l.gross!),
            calculated: l.calculated,
          ),
      ];
      notes.insert(0, 'Kreditnota: beloppen registreras som minus och dras av från utgifterna.');
    }

    final dates = _dates(rows, norm);
    final chosen = switch (prefs.dateChoice) {
      InvoiceDateChoice.invoiceDate => dates.invoice,
      InvoiceDateChoice.dueDate => dates.due,
      InvoiceDateChoice.paymentDate => dates.payment,
    };
    final date = chosen.hasValue
        ? chosen
        : (prefs.dateChoice == InvoiceDateChoice.invoiceDate
            ? chosen
            : Extracted(dates.invoice.value, Confidence.low,
                note: '${prefs.dateChoice.label} hittades inte. Datumet nedan är ett annat datum på dokumentet.'));
    return InvoiceDraft(
      isCredit: isCredit,
      dateOptions: dates.options,
      date: date.value == null ? const Extracted<String>.none() : Extracted(date.value!, date.confidence, source: date.source, note: date.note),
      dueDate: dates.due,
      supplier: _supplier(rows, norm),
      invoiceNumber: _labelledValue(rows, norm,
          ['fakturanummer', 'fakturanr', 'faktura nr', 'fakturanr.', 'invoice no', 'kvittonr', 'kvitto nr', 'kvittonummer', 'löpnr'],
          RegExp(r'[A-Za-z]{0,4}-?\d[\d\-/]{0,19}')),
      ocrReference: _labelledValue(rows, norm, ['ocr-nummer', 'ocr nr', 'ocrnr', 'ocr'], RegExp(r'\d{2,25}')),
      total: total,
      vatTotal: vatTotal,
      vatCalculated: vatCalculated,
      vatLines: vatLines,
      net: vat.net == null ? null : (isCredit ? -vat.net!.abs() : vat.net),
      totalCandidates: candidates,
      notes: notes,
    );
  }

  // ---------- Total ----------

  List<TotalCandidate> _totalCandidates(List<TextRow> rows, List<String> norm, _VatInfo vat, _Payment pay,
      {bool allowNegative = false}) {
    final out = <TotalCandidate>[];
    final pageBottom = rows.isEmpty ? 1.0 : rows.last.box.bottom;
    final vatSum = vat.explicitTotal?.$1 ?? (vat.lines.isEmpty ? null : Money.sum(vat.lines.map((l) => l.vat)));
    for (var i = 0; i < rows.length; i++) {
      final n = norm[i];
      String? label;
      double base = 0;
      for (final e in _totalLabels.entries) {
        if (!prefs.totalLabels.contains(e.value.$2)) continue;
        if (n.contains(e.key) && e.value.$1 > base) {
          label = e.key;
          base = e.value.$1;
        }
      }
      if (label == null) continue;
      if (_excludedFromTotal(n)) continue;
      // "Brutto" is also a VAT-table column header; only a row with one
      // amount counts as a total.
      if (label == 'brutto' && TextPatterns.amounts(rows[i].text).length > 1) continue;

      var amounts = TextPatterns.amounts(rows[i].text);
      // Label alone on its row: the amount may be on the next row.
      if (amounts.isEmpty && i + 1 < rows.length && TextPatterns.amounts(rows[i + 1].text).length == 1) {
        amounts = TextPatterns.amounts(rows[i + 1].text);
      }
      if (amounts.isEmpty) continue;
      final raw = amounts.last;
      if (raw.value.isZero || (raw.value.isNegative && !allowNegative)) continue;
      // Compare magnitudes; a kreditnota gets its sign afterwards.
      final a = AmountToken(raw.value.abs(), raw.start, raw.end, raw.hasDecimals);

      var score = base;
      final reasons = <String>['etikett "$label"'];
      if (!a.hasDecimals) score -= 10;
      if (rows[i].box.centerY > pageBottom * 0.4) score += 5;
      if (vat.net != null && vatSum != null) {
        final d = (vat.net! + vatSum - a.value).abs();
        if (d <= AccountingValidationEngine.totalTolerance(vat.lines.length)) {
          score += 30;
          reasons.add('stämmer med netto + moms');
        }
      }
      if (vat.grossSum != null && (vat.grossSum! - a.value).abs() <= const Money(100)) {
        score += 25;
        reasons.add('stämmer med momstabellen');
      }
      if (pay.cash != null && pay.change != null && pay.change!.ore > 0) {
        if (a.value == pay.cash! - pay.change!) {
          score += 30;
          reasons.add('stämmer med mottaget minus växel');
        } else if (a.value == pay.cash) {
          score -= 70;
          reasons.add('samma som mottaget kontant belopp');
        }
      }
      if (pay.card != null && pay.card == a.value) {
        score += 10;
        reasons.add('stämmer med kortbetalningen');
      }
      out.add(TotalCandidate(a.value, score, rows[i].text, reasons));
    }
    out.sort((x, y) => y.score.compareTo(x.score));
    return out;
  }

  _Payment _payment(List<TextRow> rows, List<String> norm) {
    Money? cash, change, card;
    for (var i = 0; i < rows.length; i++) {
      final n = norm[i];
      final a = TextPatterns.amounts(rows[i].text);
      if (a.isEmpty) continue;
      final v = a.last.value.abs();
      if (_change.any((w) => n.contains(w))) {
        change ??= v;
      } else if (_cashReceived.any((w) => n.contains(w)) && !_cardPaid.any((w) => n.contains(w))) {
        cash ??= v;
      } else if (_cardPaid.any((w) => n.contains(w)) && !n.contains('kortnr')) {
        card ??= v;
      }
    }
    return _Payment(cash, change, card);
  }

  // ---------- VAT ----------

  _VatInfo _vat(List<TextRow> rows, List<String> norm) {
    final lines = <InvoiceVatLine>[];
    (Money, String)? explicitTotal;
    Money? net;
    Money? grossSum;
    var fromTable = false;

    // 1. A VAT table: header with "moms" and "netto"/"brutto"/"exkl", rows of
    //    numbers below it. Column order is found from the arithmetic.
    for (var i = 0; i < rows.length; i++) {
      final n = norm[i];
      final isHeader = n.contains('moms') &&
          (n.contains('netto') || n.contains('brutto') || n.contains('exkl') || n.contains('underlag')) &&
          TextPatterns.amounts(rows[i].text).isEmpty;
      if (!isHeader) continue;
      final tableLines = <InvoiceVatLine>[];
      for (var j = i + 1; j < rows.length && j <= i + 6; j++) {
        final line = _tableRow(rows[j].text);
        if (line == null) {
          if (tableLines.isNotEmpty) break;
          continue;
        }
        tableLines.add(line);
      }
      if (tableLines.isNotEmpty) {
        lines.addAll(tableLines.where((l) => !l.vat.isZero || (l.net != null && !l.net!.isZero)));
        fromTable = true;
        if (tableLines.every((l) => l.net != null)) net = Money.sum(tableLines.map((l) => l.net!));
        if (tableLines.every((l) => l.gross != null)) grossSum = Money.sum(tableLines.map((l) => l.gross!));
        break;
      }
    }

    // 2. Rows like "Moms 25% 250,00", "25% moms 250,00", "Moms 6% på 491,87 29,47".
    if (lines.isEmpty && prefs.vatLabels.contains('moms')) {
      for (var i = 0; i < rows.length; i++) {
        final n = norm[i];
        if (!n.contains('moms') || n.contains('momspl') || n.contains('exkl') || n.contains('momsreg')) continue;
        final rate = TextPatterns.rate(rows[i].text);
        if (rate == null) continue;
        final a = TextPatterns.amounts(rows[i].text);
        if (a.isEmpty) continue;
        final line = _lineFromAmounts(rate, a.map((t) => t.value).toList());
        if (line != null && !line.vat.isZero) lines.add(line);
      }
    }

    // 3. Total VAT and net amount rows.
    for (var i = 0; i < rows.length; i++) {
      final n = norm[i];
      final a = TextPatterns.amounts(rows[i].text);
      if (a.isEmpty) continue;
      // "Momspliktigt belopp"/"Momspl." is the taxable base: used only to
      // check the arithmetic, never recorded as an amount.
      final isNetRow = n.contains('momspl') ||
          n.contains('exkl') ||
          n.contains('netto') ||
          n.contains('summa före moms') ||
          n.contains('underlag');
      if (isNetRow && !n.contains('brutto') && !fromTable) {
        net ??= a.last.value;
        continue;
      }
      final v = prefs.vatLabels;
      final isVatTotal = ((v.contains('total moms') &&
                  (n.contains('total moms') || n.contains('moms totalt') || n.contains('summa moms'))) ||
              (v.contains('varav moms') && n.contains('varav moms')) ||
              (v.contains('momsbelopp') && n.contains('momsbelopp')) ||
              (v.contains('moms') && RegExp(r'^moms\b[^%]*$').hasMatch(n))) &&
          TextPatterns.rate(rows[i].text) == null &&
          !n.contains('momspl') &&
          !n.contains('exkl');
      if (isVatTotal && a.length == 1) explicitTotal ??= (a.single.value, rows[i].text);
    }
    return _VatInfo(lines, explicitTotal, net, grossSum, fromTable);
  }

  /// Reads one VAT-table row: a rate followed by two or three amounts in any
  /// column order. Returns null when the numbers do not fit together.
  InvoiceVatLine? _tableRow(String row) {
    var rate = TextPatterns.rate(row);
    final amounts = TextPatterns.amounts(row).map((t) => t.value).toList();
    if (rate == null && amounts.isNotEmpty) {
      // A rate printed without "%" ("6,00") parses as 600 öre = 600 bp.
      final first = amounts.first.ore;
      if (const [600, 1200, 2500].contains(first)) {
        rate = VatRate(first);
        amounts.removeAt(0);
      }
    }
    if (rate == null || amounts.length < 2) return null;
    return _lineFromAmounts(rate, amounts, requireConsistent: true);
  }

  InvoiceVatLine? _lineFromAmounts(VatRate rate, List<Money> amounts, {bool requireConsistent = false}) {
    if (amounts.length == 1) {
      return requireConsistent ? null : InvoiceVatLine(rate: rate, vat: amounts.single);
    }
    // Try every pair (vat, base) and an optional gross.
    for (var vi = 0; vi < amounts.length; vi++) {
      for (var bi = 0; bi < amounts.length; bi++) {
        if (vi == bi) continue;
        final vat = amounts[vi];
        final base = amounts[bi];
        if (base.isZero) continue;
        final fromNet = VatCalculator.vatFromNet(base, rate);
        if ((fromNet - vat).abs() <= const Money(3)) {
          final gross = base + vat;
          final printedGross = amounts.where((x) => (x - gross).abs() <= const Money(2)).firstOrNull;
          return InvoiceVatLine(rate: rate, vat: vat, net: base, gross: printedGross ?? gross);
        }
        final fromGross = VatCalculator.vatFromGross(base, rate);
        if ((fromGross - vat).abs() <= const Money(3) && base.abs() > vat.abs()) {
          return InvoiceVatLine(rate: rate, vat: vat, gross: base, net: base - vat);
        }
      }
    }
    if (requireConsistent) return null;
    // Not consistent: keep the last amount as the printed VAT; validation
    // will flag it for the user.
    return InvoiceVatLine(rate: rate, vat: amounts.last);
  }

  // ---------- Dates ----------

  static const _invoiceDateLabels = ['fakturadatum', 'köpdatum', 'datum', 'date', 'utfärdad', 'kvittodatum'];
  static const _dueDateLabels = ['förfallodatum', 'förfallodag', 'förfaller', 'betalas senast', 'sista betalningsdag', 'oss tillhanda'];
  static const _paymentDateLabels = ['betalningsdatum', 'betaldatum', 'betalt den', 'betald den', 'inbetalningsdatum'];

  ({Extracted<String> invoice, Extracted<String> due, Extracted<String> payment, List<({String label, String date})> options})
      _dates(List<TextRow> rows, List<String> norm) {
    final found = <String, (String, String)>{}; // group -> (date, source)
    final options = <({String label, String date})>[];
    final all = <String>[];
    const names = {'invoice': 'Fakturadatum', 'due': 'Förfallodatum', 'payment': 'Betalningsdatum'};

    for (var i = 0; i < rows.length; i++) {
      final n = norm[i];
      final here = TextPatterns.dates(rows[i].text);
      all.addAll(here);
      final dueIdx = _firstIndex(n, _dueDateLabels);
      final payIdx = _firstIndex(n, _paymentDateLabels);
      // "datum" alone must not match inside "förfallodatum"/"betalningsdatum".
      final invIdx = _firstIndex(
          n,
          _invoiceDateLabels.where(
              (l) => l != 'datum' || !(n.contains('förfallodatum') || n.contains('betalningsdatum') || n.contains('betaldatum'))));
      final groups = <(String, int)>[
        if (invIdx != null) ('invoice', invIdx),
        if (dueIdx != null) ('due', dueIdx),
        if (payIdx != null) ('payment', payIdx),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      if (groups.isEmpty) continue;

      var values = here;
      var src = rows[i].text;
      if (values.isEmpty && i + 1 < rows.length) {
        values = TextPatterns.dates(rows[i + 1].text);
        src = '${rows[i].text} / ${rows[i + 1].text}';
      }
      if (values.isEmpty) continue;

      // Several labels on one header row: dates follow the label order.
      final count = values.length >= groups.length ? groups.length : 1;
      for (var g = 0; g < count; g++) {
        final key = groups[g].$1;
        if (found.containsKey(key)) continue;
        found[key] = (values[g], src);
        options.add((label: names[key]!, date: values[g]));
      }
    }

    Extracted<String> pick(String key) {
      final f = found[key];
      return f == null ? const Extracted<String>.none() : Extracted(f.$1, Confidence.high, source: f.$2);
    }

    var inv = pick('invoice');
    if (!inv.hasValue) {
      final labelled = found.values.map((f) => f.$1).toSet();
      final unique = all.toSet().where((d) => !labelled.contains(d)).toList();
      inv = unique.isEmpty
          ? const Extracted.none()
          : Extracted(unique.first, unique.length == 1 ? Confidence.medium : Confidence.low,
              note: unique.length == 1 ? null : 'Flera datum hittades');
    }
    for (final d in all.toSet()) {
      if (!options.any((o) => o.date == d)) options.add((label: 'Datum', date: d));
    }
    return (invoice: inv, due: pick('due'), payment: pick('payment'), options: options);
  }

  static int? _firstIndex(String n, Iterable<String> labels) {
    int? best;
    for (final l in labels) {
      final i = n.indexOf(l);
      if (i >= 0 && (best == null || i < best)) best = i;
    }
    return best;
  }

  // ---------- Supplier, numbers ----------

  static const _skipSupplier = [
    'faktura', 'kvitto', 'datum', 'org', 'tel', 'www', 'http', '@', 'kund', 'sida', 'kopia', 'betald', 'ocr',
    'bankgiro', 'plusgiro', 'att betala', 'adress', 'box ', 'inbetalning', 'girering',
  ];

  Extracted<String> _supplier(List<TextRow> rows, List<String> norm) {
    // A printed label wins: "Leverantör: EVRY", "Säljare: ...".
    for (var i = 0; i < rows.length; i++) {
      final m = RegExp(r'(leverantör|säljare|avsändare|betalningsmottagare)\s*[:.]?\s*(.+)$', caseSensitive: false)
          .firstMatch(rows[i].text);
      if (m != null && RegExp(r'[A-Za-zÅÄÖåäö]{2,}').hasMatch(m.group(2)!)) {
        return Extracted(_clean(m.group(2)!), Confidence.medium, source: rows[i].text);
      }
    }
    final top = rows.take((rows.length * 0.35).ceil().clamp(1, 12)).toList();
    for (final r in top) {
      if (RegExp(r'\b(AB|HB|KB|Aktiebolag|Handelsbolag|Ltd|Oy|AS|ApS)\b').hasMatch(r.text) &&
          !TextPatterns.normalize(r.text).contains('faktura')) {
        return Extracted(_clean(r.text), Confidence.medium, source: r.text);
      }
    }
    for (final r in top) {
      final n = TextPatterns.normalize(r.text);
      if (_skipSupplier.any((w) => n.contains(w))) continue;
      if (!RegExp(r'[A-Za-zÅÄÖåäö]{3,}').hasMatch(r.text)) continue;
      if (TextPatterns.amounts(r.text).isNotEmpty) continue;
      return Extracted(_clean(r.text), Confidence.low, source: r.text);
    }
    return const Extracted.none();
  }

  /// Collapses spaces and drops a cut-off label before a colon, as in
  /// "ntor: EVRY" when the photo cut "Leverantör".
  static String _clean(String s) {
    var t = s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    final m = RegExp(r'^[A-Za-zÅÄÖåäö]{1,12}\s*:\s*(.{2,})$').firstMatch(t);
    if (m != null) t = m.group(1)!.trim();
    return t;
  }

  Extracted<String> _labelledValue(List<TextRow> rows, List<String> norm, List<String> labels, RegExp value) {
    for (var i = 0; i < rows.length; i++) {
      final n = norm[i];
      for (final l in labels) {
        final idx = n.indexOf(l);
        if (idx < 0) continue;
        if (l == 'ocr' && (n.contains('ocr-nummer') || n.contains('ocr nr'))) continue;
        final after = rows[i].text.substring((idx + l.length).clamp(0, rows[i].text.length));
        final m = value.firstMatch(after.replaceFirst(RegExp(r'^[\s:.#]*'), ''));
        if (m != null && RegExp(r'\d').hasMatch(m.group(0)!)) {
          return Extracted(m.group(0)!, Confidence.medium, source: rows[i].text);
        }
        if (i + 1 < rows.length) {
          final next = value.firstMatch(rows[i + 1].text.trim());
          if (next != null && next.start == 0 && RegExp(r'\d').hasMatch(next.group(0)!)) {
            return Extracted(next.group(0)!, Confidence.low, source: '${rows[i].text} / ${rows[i + 1].text}');
          }
        }
      }
    }
    return const Extracted.none();
  }
}

class _VatInfo {
  final List<InvoiceVatLine> lines;
  final (Money, String)? explicitTotal;
  final Money? net;
  final Money? grossSum;
  final bool fromTable;
  const _VatInfo(this.lines, this.explicitTotal, this.net, this.grossSum, this.fromTable);
}

class _Payment {
  final Money? cash;
  final Money? change;
  final Money? card;
  const _Payment(this.cash, this.change, this.card);
}
