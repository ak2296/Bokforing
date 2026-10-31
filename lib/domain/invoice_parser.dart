import 'document_parser.dart';
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

  const InvoiceDraft({
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
  const InvoiceParser();

  static const _totalLabels = <String, double>{
    'summa att betala': 100,
    'belopp att betala': 100,
    'att betala': 95,
    'fakturabelopp': 90,
    'totalbelopp': 85,
    'totalt att betala': 100,
    'totalt inkl': 90,
    'summa inkl': 90,
    'totalt': 80,
    'total': 70,
    'summa': 60,
    'att erhålla': 40,
  };

  /// Rows with these words are never the invoice total.
  static const _neverTotal = [
    'kvar att betala', 'tidigare betalt', 'redan betalt', 'delsumma', 'subtotal', 'mellansumma',
    'rabatt', 'öresavrundning', 'öresutj', 'avrundning', 'växel', 'tillbaka', 'saldo', 'bonus', 'poäng', 'antal',
  ];

  /// Net amounts and VAT rows, unless the row also says the amount includes
  /// VAT or is the amount to pay.
  static const _notTotalUnlessInclusive = [
    'exkl', 'exklusive', 'netto', 'momspliktigt', 'varav moms', 'momsbelopp', 'moms',
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

    final vat = _vat(rows, norm);
    final payment = _payment(rows, norm);
    final candidates = _totalCandidates(rows, norm, vat, payment);
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

    final dates = _dates(rows, norm);
    return InvoiceDraft(
      date: dates.$1,
      dueDate: dates.$2,
      supplier: _supplier(rows, norm),
      invoiceNumber: _labelledValue(rows, norm,
          ['fakturanummer', 'fakturanr', 'faktura nr', 'fakturanr.', 'invoice no', 'kvittonr', 'kvitto nr', 'kvittonummer', 'löpnr'],
          RegExp(r'[A-Za-z]{0,4}-?\d[\d\-/]{0,19}')),
      ocrReference: _labelledValue(rows, norm, ['ocr-nummer', 'ocr nr', 'ocrnr', 'ocr'], RegExp(r'\d{2,25}')),
      total: total,
      vatTotal: vatTotal,
      vatCalculated: vatCalculated,
      vatLines: vat.lines,
      net: vat.net,
      totalCandidates: candidates,
      notes: notes,
    );
  }

  // ---------- Total ----------

  List<TotalCandidate> _totalCandidates(List<TextRow> rows, List<String> norm, _VatInfo vat, _Payment pay) {
    final out = <TotalCandidate>[];
    final pageBottom = rows.isEmpty ? 1.0 : rows.last.box.bottom;
    final vatSum = vat.explicitTotal?.$1 ?? (vat.lines.isEmpty ? null : Money.sum(vat.lines.map((l) => l.vat)));
    for (var i = 0; i < rows.length; i++) {
      final n = norm[i];
      String? label;
      double base = 0;
      for (final e in _totalLabels.entries) {
        if (n.contains(e.key) && e.value > base) {
          label = e.key;
          base = e.value;
        }
      }
      if (label == null) continue;
      if (_excludedFromTotal(n)) continue;

      var amounts = TextPatterns.amounts(rows[i].text);
      // Label alone on its row: the amount may be on the next row.
      if (amounts.isEmpty && i + 1 < rows.length && TextPatterns.amounts(rows[i + 1].text).length == 1) {
        amounts = TextPatterns.amounts(rows[i + 1].text);
      }
      if (amounts.isEmpty) continue;
      final a = amounts.last;
      if (a.value.isNegative || a.value.isZero) continue;

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
    if (lines.isEmpty) {
      for (var i = 0; i < rows.length; i++) {
        final n = norm[i];
        if (!n.contains('moms') || n.contains('momspliktig') || n.contains('exkl') || n.contains('momsreg')) continue;
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
      final isNetRow = n.contains('momspliktigt') ||
          n.contains('exkl') ||
          n.contains('netto') ||
          n.contains('summa före moms') ||
          n.contains('underlag');
      if (isNetRow && !n.contains('brutto') && !fromTable) {
        net ??= a.last.value;
        continue;
      }
      final isVatTotal = (n.contains('total moms') ||
              n.contains('moms totalt') ||
              n.contains('summa moms') ||
              n.contains('varav moms') ||
              n.contains('momsbelopp') ||
              RegExp(r'^moms\b[^%]*$').hasMatch(n)) &&
          TextPatterns.rate(rows[i].text) == null &&
          !n.contains('momspliktig') &&
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
        if ((fromGross - vat).abs() <= const Money(3) && base > vat) {
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

  (Extracted<String>, Extracted<String>) _dates(List<TextRow> rows, List<String> norm) {
    String? invoiceDate, dueDate;
    String? invoiceSrc, dueSrc;
    final all = <String>[];

    for (var i = 0; i < rows.length; i++) {
      final n = norm[i];
      final here = TextPatterns.dates(rows[i].text);
      all.addAll(here);
      final dueIdx = _firstIndex(n, _dueDateLabels);
      final invIdx = _firstIndex(n, _invoiceDateLabels.where((l) => l != 'datum' || !n.contains('förfallodatum')));
      if (dueIdx == null && invIdx == null) continue;

      var values = here;
      var src = rows[i].text;
      if (values.isEmpty && i + 1 < rows.length) {
        values = TextPatterns.dates(rows[i + 1].text);
        src = '${rows[i].text} / ${rows[i + 1].text}';
      }
      if (values.isEmpty) continue;

      if (dueIdx != null && invIdx != null && values.length >= 2) {
        // Both labels on one header row: dates follow the label order.
        final invFirst = invIdx < dueIdx;
        invoiceDate ??= invFirst ? values[0] : values[1];
        dueDate ??= invFirst ? values[1] : values[0];
        invoiceSrc ??= src;
        dueSrc ??= src;
      } else if (dueIdx != null && (invIdx == null || dueIdx <= invIdx)) {
        dueDate ??= values.first;
        dueSrc ??= src;
      } else {
        invoiceDate ??= values.first;
        invoiceSrc ??= src;
      }
    }

    Extracted<String> inv;
    if (invoiceDate != null) {
      inv = Extracted(invoiceDate, Confidence.high, source: invoiceSrc);
    } else {
      final unique = all.toSet().where((d) => d != dueDate).toList();
      inv = unique.isEmpty
          ? const Extracted.none()
          : Extracted(unique.first, unique.length == 1 ? Confidence.medium : Confidence.low,
              note: unique.length == 1 ? null : 'Flera datum hittades');
    }
    final due = dueDate == null ? const Extracted<String>.none() : Extracted(dueDate, Confidence.high, source: dueSrc);
    return (inv, due);
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
    'bankgiro', 'plusgiro', 'att betala', 'adress', 'box ',
  ];

  Extracted<String> _supplier(List<TextRow> rows, List<String> norm) {
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

  static String _clean(String s) => s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

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
