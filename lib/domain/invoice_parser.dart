import 'document_parser.dart';
import 'payment_detector.dart';
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

  final Extracted<String> bankgiro;
  final Extracted<String> plusgiro;

  /// Kvitto (paid) or faktura (to pay), from the printed signals.
  final PaymentDetection? payment;

  /// Printed payment date or the date beside a BETALD stamp.
  final String? paidDate;

  const InvoiceDraft({
    this.paidDate,
    this.bankgiro = const Extracted.none(),
    this.plusgiro = const Extracted.none(),
    this.payment,
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
  /// Supplier names already saved; matched ignoring spaces.
  final List<String> knownSuppliers;

  /// The owner's company, which is never the supplier.
  final String ownName;
  const InvoiceParser({this.knownSuppliers = const [], this.ownName = ''});

  /// Printed labels for the amount paid, Swedish and English, with a score.
  static const _totalLabels = <String, double>{
    'summa att betala': 100,
    'belopp att betala': 100,
    'totalt att betala': 100,
    'att betala': 95,
    'amount due': 95,
    'total due': 95,
    'balance due': 90,
    'amount payable': 95,
    'fakturabelopp': 90,
    'belopp (sek)': 90,
    'invoice total': 90,
    'invoice amount': 90,
    'betalt belopp': 85,
    'belopp betalt': 85,
    'amount paid': 85,
    'total paid': 85,
    'totalbelopp': 85,
    'total amount': 85,
    'totalt inkl': 90,
    'total incl': 90,
    'total including': 90,
    'grand total': 85,
    'totalt': 80,
    'total': 70,
    'bruttobelopp': 80,
    'brutto': 75,
    'gross amount': 80,
    'summa inkl': 90,
    'summa': 60,
    'att erhålla': 40,
  };

  static const _creditWords = ['kreditnota', 'kreditfaktura', 'kredit faktura', 'credit note', 'credit memo', 'kreditering'];

  /// Rows with these words are never the invoice total.
  static const _neverTotal = [
    'kvar att betala', 'tidigare betalt', 'redan betalt', 'delsumma', 'subtotal', 'sub total', 'mellansumma',
    'rabatt', 'discount', 'öresavrundning', 'öresutj', 'avrundning', 'rounding', 'växel', 'tillbaka', 'change',
    'tendered', 'saldo', 'previous balance', 'bonus', 'poäng', 'points', 'antal', 'quantity', 'qty',
    'varor', 'vara ', 'artiklar', 'artikel', 'items', 'pcs', 'st varor',
  ];

  /// Net amounts and VAT rows, unless the row also says the amount includes
  /// VAT or is the amount to pay.
  static const _notTotalUnlessInclusive = [
    'exkl', 'exklusive', 'netto', 'momspl', 'varav moms', 'momsbelopp', 'moms', 'mervärdesskatt',
    'excl', 'excluding', 'net ', 'before tax', 'taxable', 'vat', 'tax',
  ];

  static bool _excludedFromTotal(String n) {
    if (_neverTotal.any((w) => n.contains(w))) return true;
    final inclusive = n.contains('att betala') || n.contains('inkl') || n.contains('incl') ||
        n.contains('including') || n.contains('amount due') || n.contains('total due');
    return !inclusive && _notTotalUnlessInclusive.any((w) => n.contains(w));
  }

  static const _cashReceived = [
    'kontant', 'mottaget', 'erhållet', 'erhållit', 'betalt kontant', 'lämnat', 'cash', 'tendered', 'received',
  ];
  static const _change = ['växel', 'tillbaka', 'åter', 'change'];
  static const _cardPaid = [
    'kontokort', 'kort', 'betalt med', 'swish', 'kortbetalning', 'bankkort', 'card', 'visa', 'mastercard', 'paid by',
  ];

  /// VAT words in Swedish and English.
  static const _vatWords = ['moms', 'mervärdesskatt', 'vat', 'tax', 'mva'];
  static bool _hasVatWord(String n) => _vatWords.any((w) => RegExp(r'\b' + w).hasMatch(n));

  /// Net/taxable-base rows ("Momspliktigt belopp", "Netto", "Excl. VAT") and
  /// VAT registration numbers. Never a VAT amount, never recorded.
  static bool _isNetOrRegistration(String n) =>
      n.contains('momspl') ||
      n.contains('exkl') ||
      n.contains('netto') ||
      n.contains('summa före moms') ||
      n.contains('underlag') ||
      n.contains('momsreg') ||
      n.contains('moms nr') ||
      n.contains('momsnr') ||
      n.contains('moms-nr') ||
      n.contains('moms no') ||
      n.contains('excl') ||
      n.contains('excluding') ||
      n.contains('net amount') ||
      n.contains('net total') ||
      n.contains('before tax') ||
      n.contains('taxable') ||
      n.contains('vat no') ||
      n.contains('vat reg') ||
      n.contains('vat number');

  /// [paperAspect] is height / width of the paper in the photo, when known.
  @override
  InvoiceDraft parse(OcrResult ocr, {double? paperAspect}) {
    final rows = ocr.rows();
    final norm = [for (final r in rows) TextPatterns.normalize(r.text)];
    final notes = <String>[];
    final isCredit = norm.any((n) => _creditWords.any((w) => n.contains(w)));

    var vat = _vat(rows, norm);
    final payment = _payment(rows, norm);
    var candidates = _totalCandidates(rows, norm, vat, payment, allowNegative: isCredit);
    // Rows can shift, but the sums on the paper still hold. When the labels
    // give numbers that don't fit, the numbers that add up win.
    final fit = _readingFits(vat, candidates) ? null : _sumCheck(rows, norm, candidates);
    if (fit != null) {
      vat = fit;
      candidates = _totalCandidates(rows, norm, vat, payment, allowNegative: isCredit);
    } else if (candidates.isEmpty) {
      // A misread VAT must not hide the total.
      candidates = _totalCandidates(rows, norm, vat, payment, allowNegative: isCredit, trustVat: false);
    }
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
      notes.add('Ingen summa hittades på dokumentet. Fyll i summan själv.');
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
    if (vatTotal.value != null && total.value != null && vatTotal.value!.abs() > total.value!.abs()) {
      vatTotal = Extracted(vatTotal.value!, Confidence.low, source: vatTotal.source, note: 'Momsen är större än summan.');
    }

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

    // VAT that fits net + VAT = total is certain.
    if (vatTotal.value != null && total.value != null && vat.net != null) {
      final diff = (vat.net!.abs() + vatTotal.value!.abs() - total.value!.abs()).abs();
      if (diff < AccountingValidationEngine.ignoredDifference) {
        vatTotal = Extracted(vatTotal.value!, Confidence.high, source: vatTotal.source);
      }
    }

    final dates = _dates(rows, norm);
    final ocrNumber = _labelledValue(rows, norm, ['ocr-nummer', 'ocr nr', 'ocrnr', 'ocr'], RegExp(r'\d(?: ?\d){1,24}'));
    final ocrReference = ocrNumber.hasValue
        ? Extracted(ocrNumber.value!.replaceAll(' ', ''), ocrNumber.confidence, source: ocrNumber.source)
        : ocrNumber;
    var invoiceNumber = _invoiceNumber(rows, norm);
    // "Faktura/OCR-nummer 265 896 994 17" is both numbers.
    if (!invoiceNumber.hasValue && (ocrReference.source ?? '').toLowerCase().contains('faktura/ocr')) {
      invoiceNumber = ocrReference;
    }
    return InvoiceDraft(
      paidDate: dates.payment.value ?? _stampDate(rows),
      bankgiro: _giro(rows, _bankgiro),
      plusgiro: _giro(rows, _plusgiro),
      payment: const PaymentDetector().detect([for (final r in rows) r.text], paperAspect: paperAspect),
      isCredit: isCredit,
      dateOptions: dates.options,
      date: dates.invoice,
      dueDate: dates.due,
      supplier: _supplier(rows, norm),
      invoiceNumber: invoiceNumber,
      ocrReference: ocrReference,
      total: total,
      vatTotal: vatTotal,
      vatCalculated: vatCalculated,
      vatLines: vatLines,
      net: vat.net == null ? null : (isCredit ? -vat.net!.abs() : vat.net),
      totalCandidates: candidates,
      notes: notes,
    );
  }

  // ---------- Sum check ----------

  /// True when the VAT and total read from the labels are possible together.
  /// The highest Swedish rate, 25 %, is 20 % of the total.
  static bool _readingFits(_VatInfo vat, List<TotalCandidate> candidates) {
    if (candidates.isEmpty) return false;
    final total = candidates.first.value.abs();
    final vatSum = vat.explicitTotal?.$1 ?? (vat.lines.isEmpty ? null : Money.sum(vat.lines.map((l) => l.vat)));
    if (vatSum == null) return false;
    if (vat.net != null) {
      return (vat.net!.abs() + vatSum.abs() - total).abs() < AccountingValidationEngine.ignoredDifference;
    }
    return vatSum.abs().ore * 5 <= total.ore + 100;
  }

  /// Looks for three printed numbers that fit together: net × rate = VAT and
  /// net + VAT = total within rounding. Totals with a label are tried first.
  /// Only one VAT rate; a paper with several keeps what the labels gave.
  _VatInfo? _sumCheck(List<TextRow> rows, List<String> norm, List<TotalCandidate> candidates) {
    final printed = <int>{};
    final vats = <int>{};
    for (var i = 0; i < rows.length; i++) {
      for (final t in TextPatterns.amounts(rows[i].text)) {
        if (t.value.isZero || t.value.isNegative) continue;
        if (t.hasDecimals) {
          printed.add(t.value.ore);
          vats.add(t.value.ore);
        } else if (_hasVatWord(norm[i])) {
          // The separator can be lost: "58,50" read as "5850".
          vats.add(t.value.ore ~/ 100);
        }
      }
    }
    final sorted = printed.toList()..sort((a, b) => b.compareTo(a));
    for (final total in [for (final c in candidates) c.value.abs().ore, ...sorted]) {
      for (final net in sorted) {
        if (net >= total || net < 100) continue;
        for (final rate in const [VatRate.twentyFive, VatRate.twelve, VatRate.six]) {
          final expected = VatCalculator.vatFromNet(Money(net), rate).ore;
          for (final v in vats) {
            if ((v - expected).abs() > 3 || v == net) continue;
            if ((net + v - total).abs() >= Money.ignoredDifference.ore) continue;
            final gross = Money(net + v);
            return _VatInfo([InvoiceVatLine(rate: rate, vat: Money(v), net: Money(net), gross: gross)], null, Money(net), gross, true);
          }
        }
      }
    }
    return null;
  }

  // ---------- Total ----------

  List<TotalCandidate> _totalCandidates(List<TextRow> rows, List<String> norm, _VatInfo vat, _Payment pay,
      {bool allowNegative = false, bool trustVat = true}) {
    final out = <TotalCandidate>[];
    final pageBottom = rows.isEmpty ? 1.0 : rows.last.box.bottom;
    final vatSum = vat.explicitTotal?.$1 ?? (vat.lines.isEmpty ? null : Money.sum(vat.lines.map((l) => l.vat)));
    final expected = vat.net != null && vatSum != null ? vat.net! + vatSum : null;
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
      // A photo can cut or misread the first letter: "lotalt", "fotalt".
      if (label == null && n.isNotEmpty && TextPatterns.similarity(n.split(' ').first, 'totalt') >= 0.8) {
        label = 'totalt';
        base = 75;
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
      // On a curved page the amount can be on the row above: only a row that
      // is nothing but an amount counts.
      if (amounts.isEmpty && i > 0 && RegExp(r'^[\d\s.,:\-]+(kr|sek)?$').hasMatch(norm[i - 1])) {
        amounts = TextPatterns.amounts(rows[i - 1].text);
      }
      if (amounts.isEmpty) continue;
      var raw = amounts.last;
      // Digits split by OCR ("4 31 1,30"): joined they must equal net + VAT.
      if (expected != null && amounts.length > 1 && raw.value != expected) {
        final joined = Money.parse(rows[i].text.replaceAll(RegExp(r'(?<=\d)\s+(?=\d)'), '').replaceAll(RegExp(r'[^\d,.\-]'), ''));
        if (joined == expected) raw = AmountToken(expected, raw.start, raw.end, true);
      }
      if (raw.value.isZero || (raw.value.isNegative && !allowNegative)) continue;
      // A total can never be smaller than the VAT in it.
      if (trustVat && vatSum != null && raw.value.abs() < vatSum.abs()) continue;
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
    // No labelled row gave net + VAT, but an amount within rounding of it is
    // printed somewhere: a good candidate, to be checked since no label says so.
    bool near(Money v) => (v - expected!).abs() < Money.ignoredDifference;
    if (expected != null && !out.any((c) => near(c.value))) {
      for (var i = 0; i < rows.length; i++) {
        final hit = TextPatterns.amounts(rows[i].text).where((t) => near(t.value.abs())).firstOrNull;
        if (hit != null) {
          out.add(TotalCandidate(hit.value.abs(), 70, rows[i].text, const ['nära netto + moms']));
          break;
        }
      }
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
      if (_change.any((w) => n.contains(w)) || n.startsWith('ater ')) {
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
      // A heading has no amounts, but its "%" can be misread: "Moms 8 Varuvärde".
      final inHeading = TextPatterns.amounts(rows[i].text);
      final isHeader = _hasVatWord(n) &&
          (n.contains('netto') ||
              n.contains('brutto') ||
              n.contains('exkl') ||
              n.contains('underlag') ||
              n.contains('varuvärde') ||
              n.contains('varuvarde') ||
              n.contains('net') ||
              n.contains('gross') ||
              n.contains('excl')) &&
          (inHeading.isEmpty ||
              (inHeading.length == 1 && !inHeading.single.hasDecimals && inHeading.single.value < Money.kr(100)));
      if (!isHeader) continue;
      final tableLines = <InvoiceVatLine>[];
      for (var j = i + 1; j < rows.length && j <= i + 6; j++) {
        final line = _tableRow(rows[j].text);
        if (line == null) {
          // A lone amount is the end of the row above, wrapped by OCR.
          if (tableLines.isNotEmpty && !RegExp(r'^[\d\s.,]+$').hasMatch(rows[j].text.trim())) break;
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
        // "25,00 % av 15.808,60": the amount is what the VAT is calculated on.
        final base = RegExp(r'%\s*(?:av|på|of)\s+(\d[\d .,]*\d)').firstMatch(rows[i].text);
        if (base != null && !_isNetOrRegistration(n)) {
          final rate = TextPatterns.rate(rows[i].text);
          final baseAmount = Money.parse(base.group(1)!);
          if (rate != null && baseAmount != null) {
            lines.add(_lineFromBase(rate, baseAmount, rows, i));
            net ??= baseAmount;
            continue;
          }
        }
        if (!_hasVatWord(n) || _isNetOrRegistration(n)) continue;
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
      final isRegistration = const ['momsreg', 'moms nr', 'momsnr', 'moms-nr', 'moms no', 'vat no', 'vat reg', 'vat number'].any(n.contains);
      final isNetRow = _isNetOrRegistration(n) && !isRegistration;
      if (isNetRow && !n.contains('brutto') && !n.contains('gross') && !fromTable) {
        // A net of 0,00 comes from a shifted column, never from a real paper.
        if (!a.last.value.isZero) net ??= a.last.value;
        continue;
      }
      // Total VAT: "Moms", "Momsbelopp", "Varav moms", "Total moms",
      // "Mervärdesskatt", "VAT", "VAT amount", "Total VAT", "Tax".
      final isVatTotal = (n.contains('total moms') ||
              n.contains('moms totalt') ||
              n.contains('summa moms') ||
              n.contains('varav moms') ||
              n.contains('momsbelopp') ||
              n.contains('mervärdesskatt') ||
              n.contains('total vat') ||
              n.contains('vat total') ||
              n.contains('vat amount') ||
              n.contains('total tax') ||
              n.contains('tax amount') ||
              n.contains('of which vat') ||
              RegExp(r'^(moms|vat|tax|mva)\b[^%]*$').hasMatch(n)) &&
          TextPatterns.rate(rows[i].text) == null &&
          !_isNetOrRegistration(n) &&
          !n.contains('varuvärde') &&
          !n.contains('varuvarde');
      // A small whole number is a misread rate ("Moms 8"), not an amount.
      final looksLikeAmount = a.length == 1 && (a.single.hasDecimals || a.single.value >= Money.kr(30));
      if (isVatTotal && looksLikeAmount) explicitTotal ??= (a.single.value, rows[i].text);
    }
    if (net == null && lines.isNotEmpty && lines.every((l) => l.net != null)) {
      net = Money.sum(lines.map((l) => l.net!));
    }
    return _VatInfo(lines, explicitTotal, net, grossSum, fromTable);
  }

  /// The VAT on a printed base, taken from a neighbouring row when one has the
  /// right amount ("MOMS 3.952,15"), otherwise calculated and marked as such.
  InvoiceVatLine _lineFromBase(VatRate rate, Money base, List<TextRow> rows, int i) {
    final expected = VatCalculator.vatFromNet(base, rate);
    for (final j in [i - 1, i + 1, i - 2, i + 2]) {
      if (j < 0 || j >= rows.length) continue;
      for (final t in TextPatterns.amounts(rows[j].text)) {
        if ((t.value - expected).abs() < Money.ignoredDifference) {
          return InvoiceVatLine(rate: rate, vat: t.value, net: base, gross: base + t.value);
        }
      }
    }
    return InvoiceVatLine(rate: rate, vat: expected, net: base, gross: base + expected, calculated: true);
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
    // The separator can be lost or misread: "58,50" as "5850" or "58.500".
    // The printed base proves which it is.
    for (var vi = 0; vi < amounts.length; vi++) {
      for (var bi = 0; bi < amounts.length; bi++) {
        if (vi == bi || amounts[bi].isZero || amounts[vi].isZero) continue;
        final expected = VatCalculator.vatFromNet(amounts[bi], rate);
        for (final divisor in const [100, 1000]) {
          if (amounts[vi].ore % divisor != 0) continue;
          final vat = Money(amounts[vi].ore ~/ divisor);
          if ((expected - vat).abs() <= const Money(3)) {
            return InvoiceVatLine(rate: rate, vat: vat, net: amounts[bi], gross: amounts[bi] + vat);
          }
        }
      }
    }
    // Not consistent: keep the last amount as the printed VAT; validation
    // will flag it for the user.
    return InvoiceVatLine(rate: rate, vat: amounts.last);
  }

  // ---------- Dates ----------

  static const _invoiceDateLabels = [
    'fakturadatum', 'köpdatum', 'kvittodatum', 'utfärdad', 'invoice date', 'date of issue', 'issue date',
    'receipt date', 'datum', 'date',
  ];
  static const _dueDateLabels = [
    'förfallodatum', 'förfallodag', 'förfaller', 'betalas senast', 'betala senast', 'sista betalningsdag', 'oss tillhanda',
    'due date', 'payment due', 'due by', 'pay by',
  ];
  static const _paymentDateLabels = [
    'betalningsdatum', 'betaldatum', 'betalt den', 'betald den', 'inbetalningsdatum', 'payment date', 'paid on',
    'date paid',
  ];

  static const _notDocumentDate = ['återköp', 'aterköp', 'äterkop', 'aterkop', 'dagen för', 'öppet köp', 'giltig', 'bäst före'];

  /// True when a row names a due or payment date, so a bare "datum"/"date"
  /// in it is not the invoice date.
  static bool _otherDateLabel(String n) =>
      _dueDateLabels.any(n.contains) || _paymentDateLabels.any(n.contains) || n.contains('leverans');

  ({Extracted<String> invoice, Extracted<String> due, Extracted<String> payment, List<({String label, String date})> options})
      _dates(List<TextRow> rows, List<String> norm) {
    final found = <String, (String, String)>{}; // group -> (date, source)
    final options = <({String label, String date})>[];
    final unlabelled = <String>[];
    final consumed = <int>{};
    const names = {'invoice': 'Fakturadatum', 'due': 'Förfallodatum', 'payment': 'Betalningsdatum'};

    for (var i = 0; i < rows.length; i++) {
      final n = norm[i];
      // "Sista dagen för återköp" and similar are never bookkeeping dates.
      if (_notDocumentDate.any(n.contains)) continue;
      final here = TextPatterns.dates(rows[i].text);
      final dueIdx = _firstIndex(n, _dueDateLabels);
      final payIdx = _firstIndex(n, _paymentDateLabels);
      // "datum" alone must not match inside "förfallodatum"/"betalningsdatum".
      final invIdx = _firstIndex(
          n,
          _invoiceDateLabels.where(
              (l) => (l != 'datum' && l != 'date') || !_otherDateLabel(n)));
      final groups = <(String, int)>[
        if (invIdx != null) ('invoice', invIdx),
        if (dueIdx != null) ('due', dueIdx),
        if (payIdx != null) ('payment', payIdx),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      if (groups.isEmpty) {
        if (!consumed.contains(i)) unlabelled.addAll(here);
        continue;
      }

      var values = here;
      var src = rows[i].text;
      if (values.isEmpty && i + 1 < rows.length) {
        values = TextPatterns.dates(rows[i + 1].text);
        src = '${rows[i].text} / ${rows[i + 1].text}';
        if (values.isNotEmpty) consumed.add(i + 1);
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
      // An unlabelled date counts even when it equals the due date.
      final unique = unlabelled.toSet().toList();
      if (unique.isNotEmpty) {
        inv = Extracted(unique.first, unique.length == 1 ? Confidence.high : Confidence.low,
            note: unique.length == 1 ? null : 'Flera datum hittades');
      } else if (found.isNotEmpty) {
        inv = Extracted(found.values.first.$1, Confidence.low, note: 'Inget fakturadatum hittades. Kontrollera datumet.');
      }
    }
    for (final d in unlabelled.toSet()) {
      if (!options.any((o) => o.date == d)) options.add((label: 'Datum', date: d));
    }
    // "25.10.26" can be two recent dates; only a full date elsewhere settles it.
    final chosen = inv.value;
    if (chosen != null && inv.confidence == Confidence.high) {
      final showing = rows.where((r) => TextPatterns.dates(r.text).contains(chosen));
      if (showing.isNotEmpty && showing.every((r) => TextPatterns.hasAmbiguousDate(r.text))) {
        inv = Extracted(chosen, Confidence.medium, source: inv.source, note: 'Datumet kan läsas på två sätt. Kontrollera.');
      }
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

  // ---------- Payment details ----------

  /// The date beside a BETALD stamp, which OCR often splits ("2026 -10/3 0").
  String? _stampDate(List<TextRow> rows) {
    for (var i = 0; i < rows.length; i++) {
      if (!PaymentDetector.isStampRow(TextPatterns.normalize(rows[i].text))) continue;
      for (final j in [i + 1, i - 1, i + 2, i]) {
        if (j < 0 || j >= rows.length) continue;
        final found = TextPatterns.dates(rows[j].text.replaceAll(' ', '').replaceAll('/', '-'));
        if (found.isNotEmpty) return found.first;
      }
    }
    return null;
  }

  static final _bankgiro = RegExp(r'\b(bankgiro|bankgironr|bg)\b\.?\s*(nr|nummer)?\s*[:.]?\s*(\d{3,4}-\d{4})\b',
      caseSensitive: false);
  static final _plusgiro = RegExp(r'\b(plusgiro|postgiro|pg)\b\.?\s*(nr|nummer)?\s*[:.]?\s*((?:\d ?){1,7}-\d)\b',
      caseSensitive: false);

  /// Bankgiro "123-4567"/"1234-5678", plusgiro "12 34 56-7"; label required.
  Extracted<String> _giro(List<TextRow> rows, RegExp re) {
    for (var i = 0; i < rows.length; i++) {
      final m = re.firstMatch(rows[i].text);
      if (m != null) return Extracted(m.group(3)!.replaceAll(' ', ''), Confidence.medium, source: rows[i].text);
      // Label alone, number on the next row.
      if (i + 1 < rows.length && re.firstMatch(rows[i + 1].text) == null) {
        final m2 = re.firstMatch('${rows[i].text} ${rows[i + 1].text}');
        if (m2 != null) {
          return Extracted(m2.group(3)!.replaceAll(' ', ''), Confidence.low, source: '${rows[i].text} / ${rows[i + 1].text}');
        }
      }
    }
    return const Extracted.none();
  }

  // ---------- Supplier, numbers ----------

  Extracted<String> _invoiceNumber(List<TextRow> rows, List<String> norm) {
    final labelled = _labelledValue(
        rows,
        norm,
        ['fakturanummer', 'fakturanr', 'faktura nr', 'fakturanr.', 'kvittonr', 'kvitto nr', 'kvittonummer', 'löpnr', 'köpnota nr',
         'invoice number', 'invoice no', 'invoice nr', 'invoice #', 'receipt number', 'receipt no', 'receipt #'],
        RegExp(r'[A-Za-z]{0,4}-?\d[\d\-/]{0,19}'));
    if (labelled.hasValue) return labelled;
    // A plain "Nr:" in the title box, with the number on the row or the next.
    const notInvoice = ['moms', 'order', 'konto', 'leverans', 'org', 'kassa', 'tel', 'artikel', 'po '];
    final long = RegExp(r'(?<![\d-])\d{7,12}(?![\d-])');
    for (var i = 0; i < rows.length; i++) {
      final m = RegExp(r'\bnr\s*:').firstMatch(norm[i]);
      if (m == null || notInvoice.any(norm[i].substring(0, m.start).contains)) continue;
      final after = long.firstMatch(norm[i].substring(m.end));
      if (after != null) return Extracted(after.group(0)!, Confidence.medium, source: rows[i].text);
      if (i + 1 < rows.length) {
        final next = long.allMatches(rows[i + 1].text).lastOrNull;
        if (next != null) return Extracted(next.group(0)!, Confidence.low, source: '${rows[i].text} / ${rows[i + 1].text}');
      }
    }
    return const Extracted.none();
  }

  static const _skipSupplier = [
    'faktura', 'kvitto', 'datum', 'org', 'tel', 'www', 'http', '@', 'kund', 'sida', 'kopia', 'betald', 'ocr',
    'bankgiro', 'plusgiro', 'att betala', 'adress', 'box ', 'inbetalning', 'girering',
  ];

  static String _squeeze(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9åäö]'), '');

  Extracted<String> _supplier(List<TextRow> rows, List<String> norm) {
    // A supplier the owner already has, even if OCR split the name
    // ("CENTRUMGROSS ISTEN AB"). Longest name first, so "ICA Maxi" beats "ICA".
    final known = knownSuppliers.where((s) => _squeeze(s).length >= 4).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final s in known) {
      final key = _squeeze(s);
      for (final r in rows) {
        if (_squeeze(r.text).contains(key)) return Extracted(s, Confidence.high, source: r.text);
      }
    }
    // A printed label wins: "Leverantör: EVRY". "Säljare" is often the seller's
    // staff member, so it doesn't count.
    for (var i = 0; i < rows.length; i++) {
      // "Annan leverantör" on an electricity bill is someone else.
      final m = RegExp(r'(?<!annan\s)(leverantör|avsändare|betalningsmottagare)\s*[:.]?\s*(.+)$', caseSensitive: false)
          .firstMatch(rows[i].text);
      if (m != null && RegExp(r'[A-Za-zÅÄÖåäö]{2,}').hasMatch(m.group(2)!)) {
        return Extracted(_clean(m.group(2)!), Confidence.medium, source: rows[i].text);
      }
    }
    final own = _squeeze(ownName);
    bool isOwn(String t) => own.length >= 3 && _squeeze(t).contains(own);
    final top = rows.take((rows.length * 0.35).ceil().clamp(1, 12)).where((r) => !isOwn(r.text)).toList();
    // A company name: first at the top, then anywhere (often in the footer).
    // The buyer's own block ("Betalare ANKAN RESTAURANG AB") is not the supplier.
    final company = RegExp(r'\b(AB|HB|KB|Aktiebolag|Handelsbolag|Ltd|Oy|AS|ApS)\b');
    for (final r in [...top, ...rows]) {
      final n = TextPatterns.normalize(r.text);
      if (!company.hasMatch(r.text) || n.contains('faktura') || isOwn(r.text)) continue;
      final columns = r.text.split(RegExp(r'\s{3,}'));
      final at = columns.indexWhere(company.hasMatch);
      // A buyer label counts only before the name: "Axfood AB   Kund: 123" is
      // the seller, "Betalare   ANKAN AB" is the buyer.
      final upToName = columns.take(at + 1).join(' ').toLowerCase();
      if (upToName.contains('betalare') || upToName.contains('mottagare') || RegExp(r'\bkund\b').hasMatch(upToName)) continue;
      return Extracted(_clean(columns[at]), Confidence.medium, source: r.text);
    }
    // A receipt's address block: name, street, "232 37 ARLÖV". The name sits
    // two rows above the postal code; a web page title above it is skipped.
    for (var i = 2; i < top.length; i++) {
      if (RegExp(r'^\d{3} ?\d{2}\s+[A-ZÅÄÖa-zåäö]').hasMatch(top[i].text.trim())) {
        final name = top[i - 2].text;
        if (RegExp(r'[A-Za-zÅÄÖåäö]{3,}').hasMatch(name) && TextPatterns.amounts(name).isEmpty) {
          return Extracted(_clean(name), Confidence.low, source: name);
        }
      }
    }
    for (var i = 0; i < top.length; i++) {
      final r = top[i];
      final n = TextPatterns.normalize(r.text);
      if (_skipSupplier.any((w) => n.contains(w))) continue;
      if (!RegExp(r'[A-Za-zÅÄÖåäö]{3,}').hasMatch(r.text)) continue;
      if (TextPatterns.amounts(r.text).isNotEmpty) continue;
      // A misread logo ("OKEA") is printed again just below ("IKEA MALMÖ").
      final logo = r.text.trim();
      if (!logo.contains(' ')) {
        for (final next in top.skip(i + 1).take(3)) {
          final word = next.text.trim().split(' ').first;
          if (word != logo && word.length == logo.length &&
              TextPatterns.similarity(word.toLowerCase(), logo.toLowerCase()) >= 0.7) {
            return Extracted(word, Confidence.low, source: next.text);
          }
        }
      }
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
          return Extracted(m.group(0)!, Confidence.high, source: rows[i].text);
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
