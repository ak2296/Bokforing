import 'document_parser.dart';
import 'payment_detector.dart';
import 'models.dart';
import 'money.dart';
import 'ocr_models.dart';
import 'slip_code_line.dart';
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

/// A name on the paper that may be the owner's own company.
class OwnNameQuestion {
  final String name;

  /// The supplier if [name] is the owner's company; null when the paper shows
  /// no other company.
  final String? otherSupplier;

  /// Start with "Mitt företag" selected: another company is the seller.
  final bool assumeMine;
  const OwnNameQuestion(this.name, this.otherSupplier, {required this.assumeMine});
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

  /// Asked on the review screen when a name may be the owner's own.
  final OwnNameQuestion? ownNameQuestion;

  const InvoiceDraft({
    this.ownNameQuestion,
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

  /// Other names of the owner's company, as confirmed on earlier papers.
  final List<String> ownNames;
  final String ownOrgNumber;
  final String ownAddress;
  const InvoiceParser({
    this.knownSuppliers = const [],
    this.ownName = '',
    this.ownNames = const [],
    this.ownOrgNumber = '',
    this.ownAddress = '',
  });

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
    // Whole words only: "Rabatter & Krediteringar" on a specification page
    // lists credits, it is no kreditnota.
    final isCredit = norm.any((n) => _creditWords.any((w) => RegExp('(?<![a-zåäö])$w(?![a-zåäö])').hasMatch(n)));

    var vat = _vat(rows, norm);
    final payment = _payment(rows, norm);
    var candidates = _totalCandidates(rows, norm, vat, payment, allowNegative: isCredit);
    // Rows can shift, but the sums on the paper still hold. When the labels
    // give numbers that don't fit, the numbers that add up win.
    final fit = _readingFits(vat, candidates) ? null : _sumCheck(rows, norm, candidates, vat);
    if (fit != null) {
      vat = fit;
      candidates = _totalCandidates(rows, norm, vat, payment, allowNegative: isCredit);
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
    // A giro slip on its own shows no VAT, and that is no fault in the reading.
    final giroSlip = norm.any((n) => RegExp(r'girering\s*av').hasMatch(n));
    if (!vatTotal.hasValue && giroSlip) {
      vatTotal = const Extracted(Money.zero, Confidence.medium, note: 'Inbetalningskort utan moms. Kontrollera.');
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

    // A reinterpreted amount is never "sure", however well the sums fit.
    if (vat.note != null && vatTotal.value != null) {
      vatTotal = Extracted(vatTotal.value!, Confidence.medium, source: vatTotal.source, note: vat.note);
      notes.add(vat.note!);
    }

    final dates = _dates(rows, norm);
    var supplier = _resolveSupplier(rows, norm);
    final logo = _logoName(ocr);
    if (logo != null) supplier = (_checkWithLogo(supplier.$1, logo), supplier.$2);
    var ocrReference = _ocrNumber(rows, norm);
    var invoiceNumber = _invoiceNumber(rows, norm);
    // "Faktura/OCR-nummer 265 896 994 17" is both numbers.
    if (!invoiceNumber.hasValue &&
        RegExp(r'faktura(nummer|nr)?\s*/\s*ocr').hasMatch((ocrReference.source ?? '').toLowerCase())) {
      invoiceNumber = ocrReference;
    }
    var bankgiro = _giro(rows, _bankgiro);
    var plusgiro = _giro(rows, _plusgiro);

    // The slip's machine line at the bottom (OCR-B font) has a check digit in
    // every part: what passes the check is printed right, and wins over the
    // rest of the page. Checked in order: OCR, amount, bankgiro/plusgiro.
    final code = isCredit ? null : SlipCodeLine.find([for (final r in rows) r.text]);
    if (code != null) {
      if (code.ocr != null) {
        if (ocrReference.value != null && ocrReference.value != code.ocr) {
          notes.add('OCR-numret ändrades från ${ocrReference.value} till ${code.ocr} enligt inbetalningskortets kodrad.');
        }
        ocrReference = Extracted(code.ocr, Confidence.high, source: code.source, note: 'Kontrollerat mot kodraden');
      }
      final amount = code.amount;
      if (amount != null && !amount.isZero && (code.amountChecked || amount == total.value)) {
        if (total.value != null && total.value != amount) {
          notes.add('Summan ändrades från ${total.value!.format()} till ${amount.format()} enligt inbetalningskortets kodrad.');
        }
        total = Extracted(amount, Confidence.high, source: code.source, note: 'Kontrollerat mot kodraden');
      }
      final account = code.account;
      if (account != null) {
        String digits(String? s) => (s ?? '').replaceAll(RegExp(r'\D'), '');
        final isPlusgiro = digits(plusgiro.value) == account ||
            (digits(bankgiro.value) != account && code.accountCode != '41' && plusgiro.hasValue && !bankgiro.hasValue);
        if (isPlusgiro) {
          plusgiro = Extracted(SlipCodeLine.plusgiroFormat(account), Confidence.high, source: code.source);
        } else if (account.length >= 7) {
          bankgiro = Extracted(SlipCodeLine.bankgiroFormat(account), Confidence.high, source: code.source);
        }
      }
    }
    return InvoiceDraft(
      paidDate: dates.payment.value ?? _stampDate(rows),
      bankgiro: bankgiro,
      plusgiro: plusgiro,
      payment: const PaymentDetector().detect([for (final r in rows) r.text], paperAspect: paperAspect),
      isCredit: isCredit,
      dateOptions: dates.options,
      date: dates.invoice,
      dueDate: dates.due,
      supplier: supplier.$1,
      ownNameQuestion: supplier.$2,
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
    // Nor can it be a crumb of the total ("Moms 0,02" on an 18 261 kr bill).
    return vatSum.abs().ore * 5 <= total.ore + 100 && vatSum.abs().ore * 100 >= total.ore;
  }

  /// Looks for three printed numbers that fit together: net × rate = VAT and
  /// net + VAT = total within rounding. Totals with a label are tried first.
  /// Only one VAT rate; a paper with several keeps what the labels gave.
  _VatInfo? _sumCheck(List<TextRow> rows, List<String> norm, List<TotalCandidate> candidates, _VatInfo vat) {
    final printed = <int>{};
    final vats = <int>{};
    // A separator can be lost: "58,50" read as "5850". Only digits with no
    // separator on a VAT row may be read that way, and only if the sums below
    // then hold, which never happens when 5850 as written already fits.
    final withoutSeparator = <int, Money>{};
    for (var i = 0; i < rows.length; i++) {
      for (final t in TextPatterns.amounts(rows[i].text)) {
        if (t.value.isZero || t.value.isNegative) continue;
        if (t.hasDecimals) {
          printed.add(t.value.ore);
          vats.add(t.value.ore);
        } else if (t.plainDigits && t.value >= Money.kr(100) && _hasVatWord(norm[i])) {
          vats.add(t.value.ore ~/ 100);
          withoutSeparator[t.value.ore ~/ 100] = t.value;
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
            if (v == net) continue;
            // A few öre off the rate, or up to 1 % when net + VAT is the total
            // to the öre (VAT summed from rounded item lines).
            final slack = net + v == total ? (v ~/ 100).clamp(3, 1 << 30) : 3;
            if ((v - expected).abs() > slack) continue;
            if ((net + v - total).abs() >= Money.ignoredDifference.ore) continue;
            final gross = Money(net + v);
            final asRead = printed.contains(v) ? null : withoutSeparator[v];
            return _VatInfo([InvoiceVatLine(rate: rate, vat: Money(v), net: Money(net), gross: gross)], null, Money(net), gross, true,
                note: asRead == null
                    ? null
                    : 'Momsen lästes som ${asRead.ore ~/ 100} utan komma. Den tolkades som ${Money(v).format()} '
                        'eftersom ${rate.label} av ${Money(net).format()} ger det och summan då stämmer. Kontrollera mot pappret.');
          }
        }
      }
    }
    return _twoRates(sorted, candidates) ?? _vatFromNetAndTotal(vat, candidates);
  }

  /// Two VAT rates: pairs (net, VAT) at different rates whose four amounts
  /// add up to a total within rounding. The paper must also print the sum of
  /// the nets or of the VATs, so four unrelated numbers can't fit by chance.
  _VatInfo? _twoRates(List<int> printed, List<TotalCandidate> candidates) {
    final set = printed.toSet();
    final pairs = <(int, int, VatRate)>[];
    for (final net in printed) {
      if (net < 100) continue;
      for (final rate in const [VatRate.twentyFive, VatRate.twelve, VatRate.six]) {
        final expected = VatCalculator.vatFromNet(Money(net), rate).ore;
        for (final v in printed) {
          if (v != net && v > 0 && (v - expected).abs() <= 3) pairs.add((net, v, rate));
        }
      }
    }
    final totals = [for (final c in candidates) c.value.abs().ore, ...printed];
    for (var a = 0; a < pairs.length; a++) {
      for (var b = a + 1; b < pairs.length; b++) {
        final p = pairs[a], q = pairs[b];
        if (p.$3 == q.$3) continue;
        final values = {p.$1, p.$2, q.$1, q.$2};
        if (values.length < 4) continue;
        final sumNet = p.$1 + q.$1, sumVat = p.$2 + q.$2;
        if (!set.contains(sumNet) && !set.contains(sumVat)) continue;
        final total = totals.where((t) => (sumNet + sumVat - t).abs() < Money.ignoredDifference.ore).firstOrNull;
        if (total == null) continue;
        return _VatInfo([
          for (final x in [p, q]) InvoiceVatLine(rate: x.$3, vat: Money(x.$2), net: Money(x.$1), gross: Money(x.$1 + x.$2)),
        ], (Money(sumVat), 'Summa av moms per momssats'), Money(sumNet), Money(sumNet + sumVat), true);
      }
    }
    return null;
  }

  /// The VAT amount could not be read, but a printed net and a printed total
  /// fit one rate: the VAT is the difference, to be checked.
  _VatInfo? _vatFromNetAndTotal(_VatInfo vat, List<TotalCandidate> candidates) {
    final net = vat.net;
    // Only when a VAT amount was printed and read wrong; with none printed the
    // VAT is reconstructed as summa minus netto further on.
    if (vat.explicitTotal == null && vat.lines.isEmpty) return null;
    if (net == null || net.isZero || candidates.isEmpty) return null;
    final total = candidates.first.value.abs();
    for (final rate in const [VatRate.twentyFive, VatRate.twelve, VatRate.six]) {
      final v = VatCalculator.vatFromNet(net.abs(), rate);
      if ((net.abs() + v - total).abs() >= Money.ignoredDifference) continue;
      final diff = total - net.abs();
      return _VatInfo([InvoiceVatLine(rate: rate, vat: diff, net: net.abs(), gross: total, calculated: true)], null, net.abs(),
          total, false,
          note: 'Momsen kunde inte läsas säkert. Den räknades fram som summan minus nettot '
              '(${rate.label} av ${net.abs().format()}). Kontrollera mot pappret.');
    }
    return null;
  }

  // ---------- Total ----------

  List<TotalCandidate> _totalCandidates(List<TextRow> rows, List<String> norm, _VatInfo vat, _Payment pay,
      {bool allowNegative = false}) {
    final out = <TotalCandidate>[];
    final pageBottom = rows.isEmpty ? 1.0 : rows.last.box.bottom;
    final vatSum = vat.explicitTotal?.$1 ?? (vat.lines.isEmpty ? null : Money.sum(vat.lines.map((l) => l.vat)));
    final expected = vat.net != null && vatSum != null ? vat.net! + vatSum : null;
    for (var i = 0; i < rows.length; i++) {
      final n = norm[i];
      // Positions are taken in the row as printed: collapsing its spaces
      // would join "3   125,00" into one number.
      final lower = rows[i].text.toLowerCase();
      String? label;
      double base = 0;
      var labelAt = -1, labelEnd = -1;
      for (final e in _totalLabels.entries) {
        if (e.value <= base || !n.contains(e.key)) continue;
        // The last place the label is printed: "SUBTOTAL 1891,76 ATT BETALA 1892,00".
        final at = RegExp(e.key.split(' ').map(RegExp.escape).join(r'\s+')).allMatches(lower).lastOrNull;
        if (at == null) continue;
        label = e.key;
        base = e.value;
        labelAt = at.start;
        labelEnd = at.end;
      }
      // A photo can cut or misread the first letter: "lotalt", "fotalt",
      // "otaler".
      if (label == null && n.isNotEmpty) {
        final first = RegExp(r'\S+').firstMatch(lower);
        final word = first?[0] ?? '';
        if (TextPatterns.similarity(word, 'totalt') >= 0.8 || TextPatterns.similarity(word, 'totaler') >= 0.8) {
          label = 'totalt';
          base = 75;
          labelAt = first!.start;
          labelEnd = first.end;
        }
      }
      if (label == null) continue;

      // Only the amounts printed after the label belong to it, up to the next
      // word. Amounts before it belong to other labels on the same row.
      final run = _amountsAfter(lower, labelEnd);
      // Words that rule a total out count only next to its label and amount.
      final windowEnd = run.isNotEmpty ? run.last.end : lower.length;
      if (_excludedFromTotal(TextPatterns.normalize(lower.substring((labelAt - 15).clamp(0, labelAt), windowEnd)))) continue;
      // "Brutto" is also a VAT-table column header; only a row with one
      // amount counts as a total.
      if (label == 'brutto' && run.length > 1) continue;

      var amounts = run;
      var joinSource = rows[i].text.substring(labelEnd);
      // Label alone on its row: the amount may be on the next row, when that
      // row is nothing but amounts.
      if (amounts.isEmpty && i + 1 < rows.length && _onlyAmounts(norm[i + 1])) {
        amounts = TextPatterns.amounts(rows[i + 1].text);
        joinSource = rows[i + 1].text;
      }
      // On a curved page the amount can be on the row above: only a row that
      // is nothing but an amount counts.
      if (amounts.isEmpty && i > 0 && RegExp(r'^[\d\s.,:\-]+(kr|sek)?$').hasMatch(norm[i - 1])) {
        amounts = TextPatterns.amounts(rows[i - 1].text);
        joinSource = rows[i - 1].text;
      }
      if (amounts.isEmpty) continue;
      var raw = amounts.last;
      // Digits split by OCR ("4 31 1,30"): joined they must equal net + VAT.
      if (expected != null && amounts.length > 1 && raw.value != expected) {
        final joined = Money.parse(joinSource.replaceAll(RegExp(r'(?<=\d)\s+(?=\d)'), '').replaceAll(RegExp(r'[^\d,.\-]'), ''));
        if (joined == expected) raw = AmountToken(expected, raw.start, raw.end, true);
      }
      if (raw.value.isZero || (raw.value.isNegative && !allowNegative)) continue;
      // A total can never be smaller than the VAT in it.
      if (vatSum != null && raw.value.abs() < vatSum.abs()) continue;
      // Compare magnitudes; a kreditnota gets its sign afterwards.
      final a = AmountToken(raw.value.abs(), raw.start, raw.end, raw.hasDecimals);

      var score = base;
      final reasons = <String>['etikett "$label"'];
      if (!a.hasDecimals) score -= 10;
      // Nor smaller than the printed net amount.
      if (vat.net != null && a.value < vat.net!.abs() - Money.ignoredDifference) {
        score -= 40;
        reasons.add('mindre än nettobeloppet');
      }
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
    // A giro slip prints kronor and öre apart and no label: "159 00   4 >",
    // read as "4 >   159 00" when the slip was upside down.
    if (out.isEmpty) {
      for (var i = 0; i < rows.length; i++) {
        final m = RegExp(r'(?<!\d)(\d[\d ]{0,8}?) (\d{2})\s+\d\s*>').firstMatch(rows[i].text) ??
            RegExp(r'(?<!\d)\d\s*>\s+(\d[\d ]{0,8}?) (\d{2})(?!\d)').firstMatch(rows[i].text);
        final slip = m == null ? null : Money.parse('${m[1]!.replaceAll(' ', '')},${m[2]}');
        if (slip != null && !slip.isZero) {
          out.add(TotalCandidate(slip, 75, rows[i].text, const ['beloppet på inbetalningskortet']));
          break;
        }
      }
    }
    // "159 00" alone on its row, beside the slip's "#" or ">" code line.
    if (out.isEmpty) {
      bool nearCodeLine(int i) {
        for (var j = i - 2; j <= i + 2; j++) {
          if (j != i && j >= 0 && j < rows.length && RegExp(r'[#>]').hasMatch(rows[j].text)) return true;
        }
        return false;
      }

      for (var i = 0; i < rows.length; i++) {
        final m = RegExp(r'^\s*(\d{1,3}(?: \d{3})*) (\d{2})\s*$').firstMatch(rows[i].text);
        final slip = m == null ? null : Money.parse('${m[1]!.replaceAll(' ', '')},${m[2]}');
        if (slip != null && !slip.isZero && nearCodeLine(i)) {
          out.add(TotalCandidate(slip, 65, rows[i].text, const ['beloppet på inbetalningskortet']));
          break;
        }
      }
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

  /// The amounts printed right after [from] in [n]: the first one, and the
  /// ones that follow it with no word between them ("Summa 1 124,20 233,55
  /// 1357,75"). A word ends the run: "Totalt 450,00 Moms 90,00".
  static List<AmountToken> _amountsAfter(String n, int from) {
    final after = TextPatterns.amounts(n).where((t) => t.start >= from).toList();
    final run = <AmountToken>[];
    for (final t in after) {
      if (run.isNotEmpty) {
        final gap = n.substring(run.last.end, t.start).toLowerCase().replaceAll(RegExp(r'\b(kr|sek|kronor)\b'), '');
        if (RegExp(r'[a-zåäö]{3,}').hasMatch(gap)) break;
      }
      run.add(t);
    }
    return run;
  }

  /// A row that is nothing but amounts ("kr", "sek", "kronor" allowed).
  static bool _onlyAmounts(String n) =>
      TextPatterns.amounts(n).isNotEmpty &&
      !RegExp(r'[a-zåäö]{2,}').hasMatch(n.replaceAll(RegExp(r'\b(kr|sek|kronor)\b'), ''));

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
    // A sum row with net, VAT and gross that add up to the öre ("Summa
    // 1 124,20 233,55 1 357,75") is the strongest VAT source on the page.
    final triple = _sumRow(rows, norm);
    if (triple != null && explicitTotal?.$1 != triple.vat) {
      explicitTotal = (triple.vat, triple.row);
      net = triple.net;
      grossSum = triple.gross;
      if (lines.isNotEmpty && Money.sum(lines.map((l) => l.vat)) != triple.vat) {
        lines.clear();
        fromTable = false;
      }
    }
    if (net == null && lines.isNotEmpty && lines.every((l) => l.net != null)) {
      net = Money.sum(lines.map((l) => l.net!));
    }
    return _VatInfo(lines, explicitTotal, net, grossSum, fromTable);
  }

  ({Money net, Money vat, Money gross, String row})? _sumRow(List<TextRow> rows, List<String> norm) {
    for (var i = 0; i < rows.length; i++) {
      final n = norm[i];
      if (!RegExp(r'\b(summa|totalt?|totaler|total amount)\b').hasMatch(n)) continue;
      if (n.contains('delsumma') || n.contains('subtotal') || n.contains('rabatt')) continue;
      final a = [for (final t in TextPatterns.amounts(rows[i].text)) if (t.hasDecimals && !t.value.isNegative) t.value];
      if (a.length < 3) continue;
      for (var k = 0; k + 2 < a.length; k++) {
        final net = a[k], vat = a[k + 1], gross = a[k + 2];
        if (net + vat != gross || vat.isZero) continue;
        // 6 % to 25 % of the net, the Swedish rates and their mixes.
        if (vat.ore * 1000 < net.ore * 56 || vat.ore * 1000 > net.ore * 251) continue;
        return (net: net, vat: vat, gross: gross, row: rows[i].text);
      }
    }
    return null;
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
    final tokens = TextPatterns.amounts(row);
    var amounts = tokens.map((t) => t.value).toList();
    if (rate == null && tokens.isNotEmpty) {
      // A rate printed without "%" ("6,00"), first in the row, possibly glued
      // to dots ("Stan..25,00").
      final m = RegExp(r'(?<![\d,])(6|12|25)[,.]00(?!\d)').firstMatch(row);
      if (m != null && tokens.every((t) => t.end <= m.start || t.start >= m.start)) {
        final others = tokens.where((t) => t.start >= m.end || t.end <= m.start).toList();
        if (others.isNotEmpty && others.first.start >= m.end) {
          rate = VatRate(int.parse(m[1]!) * 100);
          amounts = others.map((t) => t.value).toList();
        }
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
        final gross = base + vat;
        // Rows summed from rounded item VAT can be a few öre off; up to 1 %
        // of the VAT is accepted when net + VAT = gross is printed exactly.
        final exactGross = amounts.any((x) => x == gross && x != vat && x != base);
        final slack = exactGross ? Money((vat.abs().ore ~/ 100).clamp(3, 1 << 30)) : const Money(3);
        if ((fromNet - vat).abs() <= slack) {
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

  static const _invoiceDateLabels = [
    'fakturadatum', 'faktureringsdag', 'faktureringsdatum', 'köpdatum', 'kvittodatum', 'utfärdad', 'invoice date',
    'date of issue', 'issue date', 'receipt date', 'datum', 'date',
  ];
  static const _dueDateLabels = [
    'förfallodatum', 'forfallodatum', 'förfallodag', 'forfallodag', 'förfaller', 'betalas senast', 'betala senast',
    'sista betalningsdag', 'oss tillhanda', 'due date', 'payment due', 'due by', 'pay by',
  ];

  /// "Förtallodatum", "Forfallodatun": a misread due-date label.
  static int? _fuzzyDueLabel(String n) {
    for (final m in RegExp(r'[a-zåäö]{9,}').allMatches(n)) {
      if (TextPatterns.similarity(m[0]!, 'förfallodatum') >= 0.8 || TextPatterns.similarity(m[0]!, 'förfallodag') >= 0.8) {
        return m.start;
      }
    }
    return null;
  }
  static const _paymentDateLabels = [
    'betalningsdatum', 'betaldatum', 'betalt den', 'betald den', 'inbetalningsdatum', 'payment date', 'paid on',
    'date paid',
  ];

  static const _notDocumentDate = ['återköp', 'aterköp', 'äterkop', 'aterkop', 'dagen för', 'öppet köp', 'giltig', 'bäst före'];

  /// True when a row names a due or payment date, so a bare "datum"/"date"
  /// in it is not the invoice date.
  static bool _otherDateLabel(String n) =>
      _dueDateLabels.any(n.contains) || _paymentDateLabels.any(n.contains) || n.contains('leverans') ||
      _fuzzyDueLabel(n) != null;

  /// The date labels in a row, in the order they are printed.
  static List<(String, int)> _dateGroups(String n) {
    final dueIdx = _firstIndex(n, _dueDateLabels) ?? _fuzzyDueLabel(n);
    final payIdx = _firstIndex(n, _paymentDateLabels);
    // "datum" alone must not match inside "förfallodatum"/"betalningsdatum".
    final invIdx = _firstIndex(n, _invoiceDateLabels.where((l) => (l != 'datum' && l != 'date') || !_otherDateLabel(n)));
    return <(String, int)>[
      if (invIdx != null) ('invoice', invIdx),
      if (dueIdx != null) ('due', dueIdx),
      if (payIdx != null) ('payment', payIdx),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
  }

  ({Extracted<String> invoice, Extracted<String> due, Extracted<String> payment, List<({String label, String date})> options})
      _dates(List<TextRow> rows, List<String> norm) {
    final found = <String, (String, String)>{}; // group -> (date, source)
    final options = <({String label, String date})>[];
    final unlabelled = <(int, String)>[];
    final consumed = <int>{};
    const names = {'invoice': 'Fakturadatum', 'due': 'Förfallodatum', 'payment': 'Betalningsdatum'};
    bool skipped(int j) => _notDocumentDate.any(norm[j].contains);
    // A row with a date and no date label of its own, free to lend its date.
    bool lone(int j) =>
        j >= 0 && j < rows.length && !consumed.contains(j) && !skipped(j) && _dateGroups(norm[j]).isEmpty &&
        TextPatterns.dates(rows[j].text).isNotEmpty;
    bool blank(int j) => j < rows.length && _dateGroups(norm[j]).isEmpty && TextPatterns.dates(rows[j].text).isEmpty;

    for (var i = 0; i < rows.length; i++) {
      final n = norm[i];
      // "Sista dagen för återköp" and similar are never bookkeeping dates.
      if (skipped(i)) continue;
      final here = TextPatterns.dates(rows[i].text);
      final groups = _dateGroups(n);
      if (groups.isEmpty) {
        if (!consumed.contains(i)) unlabelled.addAll([for (final d in here) (i, d)]);
        continue;
      }

      var values = here;
      var src = rows[i].text;
      // A label alone: its date is on the row below, or one further down past
      // a row with no date, or on the row above when a curved page lifted it.
      if (values.isEmpty) {
        final j = lone(i + 1)
            ? i + 1
            : lone(i - 1)
                ? i - 1
                : blank(i + 1) && lone(i + 2)
                    ? i + 2
                    : null;
        if (j != null) {
          values = TextPatterns.dates(rows[j].text);
          src = '${rows[i].text} / ${rows[j].text}';
          consumed.add(j);
          unlabelled.removeWhere((u) => u.$1 == j);
        }
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
      final unique = unlabelled.map((u) => u.$2).toSet().toList();
      if (unique.isNotEmpty) {
        inv = Extracted(unique.first, unique.length == 1 ? Confidence.high : Confidence.low,
            note: unique.length == 1 ? null : 'Flera datum hittades');
      } else if (found.isNotEmpty) {
        inv = Extracted(found.values.first.$1, Confidence.low, note: 'Inget fakturadatum hittades. Kontrollera datumet.');
      }
    }
    for (final d in unlabelled.map((u) => u.$2).toSet()) {
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

  static final _bankgiro = (
    RegExp(r'\b(bank[gq]iro(?:nr|nummer)?|bg)\b', caseSensitive: false),
    RegExp(r'(?<![\d-])\d{3,4}-\d{4}(?![\d-])'),
  );
  static final _plusgiro = (
    RegExp(r'\b(plus[gq]iro(?:nr|nummer)?|post[gq]iro(?:nr|nummer)?|pg)\b', caseSensitive: false),
    RegExp(r'(?<![\d-])(?:\d ?){1,7}-\d(?![\d-])'),
  );

  /// Bankgiro "123-4567"/"1234-5678", plusgiro "12 34 56-7"; label required.
  /// The number follows the label on its row, or is on one of the two rows
  /// below a label that stands alone ("Till bankgironr").
  Extracted<String> _giro(List<TextRow> rows, (RegExp, RegExp) re) {
    final (label, number) = re;
    for (var i = 0; i < rows.length; i++) {
      final l = label.allMatches(rows[i].text).lastOrNull;
      if (l == null) continue;
      final m = number.firstMatch(rows[i].text.substring(l.end));
      if (m != null) return Extracted(m[0]!.replaceAll(' ', ''), Confidence.medium, source: rows[i].text);
      if (number.hasMatch(rows[i].text)) continue;
      for (var j = i + 1; j <= i + 2 && j < rows.length; j++) {
        if (label.hasMatch(rows[j].text)) break;
        final below = number.firstMatch(rows[j].text);
        if (below != null) {
          return Extracted(below[0]!.replaceAll(' ', ''), Confidence.low, source: '${rows[i].text} / ${rows[j].text}');
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
        ['fakturanummer', 'fakturanr', 'faktura nr', 'fakturanr.', 'kvittonr', 'kvitto nr', 'kvittonummer', 'löpnr', 'köpnota nr', 'avinr', 'avi nr', 'avinummer',
         'invoice number', 'invoice no', 'invoice nr', 'invoice #', 'receipt number', 'receipt no', 'receipt #'],
        RegExp(r'[A-Za-z]{0,4}-?\d[\d\-/]{0,19}'),
        below: RegExp(r'(?<![\d\-,.])\d{4,12}(?![\d\-,.])'),
        fuzzy: 'fakturanummer');
    if (labelled.hasValue) return labelled;
    // A plain "Nr:" in the title box, with the number on the row or the next.
    const notInvoice = ['moms', 'vat', 'order', 'konto', 'leverans', 'org', 'kassa', 'tel', 'artikel', 'po '];
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
    'faktura', 'kvitto', 'datum', 'org', 'organisation', 'tel', 'telefon', 'www', 'http', '@', 'kund', 'kundnr',
    'kundnummer', 'sida', 'kopia', 'betald', 'ocr', 'bankgiro', 'plusgiro', 'att betala', 'adress', 'box ',
    'inbetalning', 'girering',
  ];

  static String _squeeze(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9åäö]'), '');

  /// The supplier, and a question when a name may be the owner's own company.
  /// The org number and address decide first; only a close name with no such
  /// proof is asked about.
  (Extracted<String>, OwnNameQuestion?) _resolveSupplier(List<TextRow> rows, List<String> norm) {
    final mine = _namesAtOwnAddress(rows);
    final first = _supplier(rows, norm, mine);
    final name = first.value;
    if (name == null || knownSuppliers.contains(name) || !_closeToOwn(name)) return (first, null);
    // A different org number beside the name: a real supplier with a similar name.
    final at = rows.indexWhere((r) => r.text.contains(name));
    if (at >= 0 && _otherOrgNear(rows, at)) return (first, null);
    final other = _supplier(rows, norm, {...mine, _squeeze(name)});
    final otherName = other.value;
    if (otherName == null) return (first, OwnNameQuestion(name, null, assumeMine: false));
    if (_ownOrgOnPaper(rows)) return (other, null);
    return (other, OwnNameQuestion(name, otherName, assumeMine: true));
  }

  /// The company name printed as a logo: the tallest text in the top third of
  /// the page, clearly taller than ordinary text. Null when nothing stands out.
  String? _logoName(OcrResult ocr) {
    final lines = ocr.lines.where((l) => !ocr.isMarginText(l)).toList();
    if (lines.length < 4) return null;
    final heights = lines.map((l) => l.box.height).toList()..sort();
    final median = heights[heights.length ~/ 2];
    if (median <= 0) return null;
    final top = lines.map((l) => l.box.top).reduce((a, b) => a < b ? a : b);
    final bottom = lines.map((l) => l.box.bottom).reduce((a, b) => a > b ? a : b);
    OcrLine? best;
    for (final l in lines) {
      if (l.box.top > top + (bottom - top) / 3) continue;
      if (l.box.height < median * 1.6) continue;
      final t = l.text.trim();
      if (!RegExp(r'[A-Za-zÅÄÖåäö]{3,}').hasMatch(t) || TextPatterns.amounts(t).isNotEmpty) continue;
      final n = TextPatterns.normalize(t);
      if (const ['faktura', 'kvitto', 'invoice', 'receipt', 'kreditnota', 'specifikation', 'inbetalning', 'kopia']
          .any(n.contains)) {
        continue;
      }
      if (_closeToOwn(t) || [ownName, ...ownNames].any((o) => _squeeze(o).length >= 3 && _squeeze(t).contains(_squeeze(o)))) {
        continue;
      }
      if (best == null || l.box.height > best.box.height) best = l;
    }
    return best?.text.trim();
  }

  /// Uses the logo name to back up or confirm the supplier read from the text.
  Extracted<String> _checkWithLogo(Extracted<String> supplier, String logo) {
    String fold(String s) => _squeeze(s).replaceAll(RegExp('[åä]'), 'a').replaceAll('ö', 'o');
    final name = supplier.value;
    if (name == null) return Extracted(logo, Confidence.medium, source: logo, note: 'Namnet i logotypen');
    final a = fold(name), b = fold(logo);
    final agree = b.length >= 3 && (a.contains(b) || b.contains(a) || TextPatterns.similarity(a, b) >= 0.8);
    if (agree) {
      // Two places on the paper give the same name.
      return supplier.confidence == Confidence.low
          ? Extracted(name, Confidence.medium, source: supplier.source, note: 'Stämmer med logotypen')
          : supplier;
    }
    // A guess from the page loses to the logo; a labelled or known name stays.
    if (supplier.confidence == Confidence.low) {
      return Extracted(logo, Confidence.medium, source: logo, note: 'Namnet i logotypen');
    }
    return supplier;
  }

  /// Names printed directly above the owner's street and number, in the same
  /// column. The number matters: the seller can be on the same street.
  Set<String> _namesAtOwnAddress(List<TextRow> rows) {
    final m = RegExp(r'^\s*([A-Za-zÅÄÖåäö]{4,})\.?\s*(\d+)').firstMatch(ownAddress);
    final found = <String>{};
    if (m == null) return found;
    final street = m[1]!.toLowerCase();
    bool isStreet(String column) => RegExp(r'([A-Za-zÅÄÖåäö]{4,})\.?\s*(\d+)').allMatches(column).any(
        (w) => w[2] == m[2] && TextPatterns.similarity(w[1]!.toLowerCase(), street) >= 0.8);
    final split = RegExp(r'\s{3,}');
    for (var i = 1; i < rows.length; i++) {
      final columns = rows[i].text.split(split);
      final k = columns.indexWhere(isStreet);
      if (k < 0) continue;
      final above = rows[i - 1].text.split(split);
      final printed = above[k < above.length ? k : above.length - 1];
      // A company form names a company; it is the owner's only if it is close
      // to the owner's name ("Axfood Snabbgross AB" on the same street number
      // is the seller).
      if (RegExp(r'\b(AB|HB|KB|Aktiebolag|Handelsbolag)\b').hasMatch(printed) && !_closeToOwn(printed)) continue;
      final name = _squeeze(printed);
      if (name.length >= 3) found.add(name);
    }
    return found;
  }

  bool _closeToOwn(String name) {
    String firstWord(String s) => s.trim().split(RegExp(r'\s+')).first.toLowerCase();
    return [ownName, ...ownNames].where((o) => o.trim().isNotEmpty).any((o) {
      final a = firstWord(name);
      if (a.length >= 4 && TextPatterns.similarity(a, firstWord(o)) >= 0.8) return true;
      return TextPatterns.similarity(_squeeze(name), _squeeze(o)) >= 0.7;
    });
  }

  String get _ownOrgDigits => ownOrgNumber.replaceAll(RegExp(r'\D'), '');

  bool _ownOrgOnPaper(List<TextRow> rows) =>
      _ownOrgDigits.length == 10 && rows.any((r) => r.text.replaceAll(RegExp(r'\D'), '').contains(_ownOrgDigits));

  bool _otherOrgNear(List<TextRow> rows, int at) {
    for (var i = at - 1; i <= at + 1; i++) {
      if (i < 0 || i >= rows.length) continue;
      for (final m in RegExp(r'(?<!\d)\d{6}-?\d{4}(?!\d)').allMatches(rows[i].text)) {
        if (m[0]!.replaceAll('-', '') != _ownOrgDigits) return true;
      }
    }
    return false;
  }

  /// [skip] holds squeezed names that are the owner's own on this paper.
  Extracted<String> _supplier(List<TextRow> rows, List<String> norm, Set<String> skip) {
    final mine = {
      for (final o in [ownName, ...ownNames]) _squeeze(o),
      ...skip,
    }.where((o) => o.length >= 3);
    bool isOwn(String t) => mine.any(_squeeze(t).contains);
    // A supplier the owner already has, even if OCR split the name
    // ("CENTRUMGROSS ISTEN AB"). Longest name first, so "ICA Maxi" beats "ICA".
    final known = knownSuppliers.where((s) => _squeeze(s).length >= 4 && !isOwn(s)).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final s in known) {
      final key = _squeeze(s);
      for (final r in rows) {
        if (_squeeze(r.text).contains(key)) return Extracted(s, Confidence.high, source: r.text);
      }
    }
    // A printed label wins: "Leverantör: EVRY". "Säljare" is often the seller's
    // staff member, so it doesn't count.
    // "Betalningsmottagare (endast namn)": the note in brackets is no name.
    String unbracketed(String s) => s.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    final letters = RegExp(r'[A-Za-zÅÄÖåäö]{3,}');
    bool giroWord(String s) => RegExp(r'giro|girering', caseSensitive: false).hasMatch(s);
    // "Betalningsmottagare" as a heading, the name below it after the number.
    for (var i = 0; i + 1 < rows.length; i++) {
      if (!RegExp(r'(betalningsmottagare|utställare)\W*$', caseSensitive: false).hasMatch(unbracketed(rows[i].text))) continue;
      final name = rows[i + 1].text.split(RegExp(r'\s{3,}')).lastWhere(
          (c) => letters.hasMatch(c) && !giroWord(c),
          orElse: () => '');
      if (name.isNotEmpty) return Extracted(_clean(name), Confidence.medium, source: rows[i + 1].text);
    }
    for (var i = 0; i < rows.length; i++) {
      // "Annan leverantör" on an electricity bill is someone else.
      final m = RegExp(r'(?<!annan\s)(leverantör|avsändare|betalningsmottagare|utställare)\s*[:.]?\s*(.+)$', caseSensitive: false)
          .firstMatch(unbracketed(rows[i].text));
      if (m != null && RegExp(r'[A-Za-zÅÄÖåäö]{2,}').hasMatch(m.group(2)!) && !giroWord(m.group(2)!)) {
        return Extracted(_clean(m.group(2)!), Confidence.medium, source: rows[i].text);
      }
    }
    final top = rows.take((rows.length * 0.35).ceil().clamp(1, 12)).where((r) => !isOwn(r.text)).toList();
    // A company name: first at the top, then anywhere (often in the footer).
    // The buyer's own block ("Betalare ANKAN RESTAURANG AB") is not the supplier.
    final company = RegExp(r'\b(AB|HB|KB|Aktiebolag|Handelsbolag|Ltd|Oy|AS|ApS)\b');
    // A company named inside a sentence ("avtal med Svensk Scen & Film AB
    // (org.nr …)") is not the sender.
    bool inSentence(String column) {
      final m = company.firstMatch(column);
      if (m == null) return true;
      final before = column.substring(0, m.start).trim();
      final words = before.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.length > 5 || (words.isNotEmpty && RegExp(r'^[a-zåäö]{3,}$').hasMatch(words.first) && words.length > 2)) {
        return true;
      }
      // The sentence goes on after the name and its bracket.
      final after = unbracketed(column.substring(m.end)).split(RegExp(r'\s+')).where((w) => letters.hasMatch(w));
      return after.length > 3;
    }

    String fold(String s) => _squeeze(s).replaceAll(RegExp('[åä]'), 'a').replaceAll('ö', 'o');
    for (final r in [...top, ...rows]) {
      final n = TextPatterns.normalize(r.text);
      if (!company.hasMatch(r.text) || n.contains('faktura')) continue;
      final columns = r.text.split(RegExp(r'\s{3,}'));
      final at = columns.indexWhere((c) => company.hasMatch(c) && !isOwn(c) && !inSentence(c));
      if (at < 0) continue;
      // A buyer label counts only before the name: "Axfood AB   Kund: 123" is
      // the seller, "Betalare   ANKAN AB" is the buyer.
      final upToName = columns.take(at + 1).join(' ').toLowerCase();
      if (upToName.contains('betalare') || upToName.contains('mottagare') || RegExp(r'\bkund\b').hasMatch(upToName)) continue;
      var name = _clean(columns[at].split('(').first);
      // A cut name at the top ("osT AB") printed whole in the footer
      // ("Rest Lillebror Öst AB").
      final key = fold(name);
      if (key.length >= 3) {
        for (final other in rows) {
          for (final c in other.text.split(RegExp(r'\s{3,}'))) {
            final whole = _clean(c.split('(').first);
            if (company.hasMatch(whole) && !inSentence(whole) && !isOwn(whole) &&
                fold(whole).length > key.length && fold(whole).endsWith(key)) {
              name = whole;
            }
          }
        }
      }
      return Extracted(name, Confidence.medium, source: r.text);
    }
    // A short skip word counts only as a word of its own: "tel" skips "Tel:",
    // never "Telenor".
    bool skipWord(String n) => _skipSupplier.any((w) => RegExp(r'^[a-zåäö]{1,4}$').hasMatch(w)
        ? RegExp('(?<![a-zåäö])$w(?![a-zåäö])').hasMatch(n)
        : n.contains(w));
    // A receipt's address block: name, street, "232 37 ARLÖV". The name sits
    // above the street, in the first column; labels and a web page title
    // above it are skipped.
    for (var i = 2; i < top.length; i++) {
      if (!RegExp(r'^\d{3} ?\d{2}\s+[A-ZÅÄÖa-zåäö]').hasMatch(top[i].text.trim())) continue;
      for (var k = i - 2; k >= 0 && k >= i - 4; k--) {
        final name = top[k].text.split(RegExp(r'\s{3,}')).first;
        if (!letters.hasMatch(name) || TextPatterns.amounts(name).isNotEmpty) continue;
        if (skipWord(TextPatterns.normalize(name)) || _closeToOwn(name)) continue;
        return Extracted(_clean(name), Confidence.low, source: top[k].text);
      }
    }
    for (var i = 0; i < top.length; i++) {
      final r = top[i];
      final n = TextPatterns.normalize(r.text);
      if (skipWord(n)) continue;
      if (RegExp(r'^\W*(kronor|öre)\W*$').hasMatch(n)) continue;
      if (!letters.hasMatch(r.text)) continue;
      if (TextPatterns.amounts(r.text).isNotEmpty) continue;
      if (!letters.hasMatch(_clean(r.text))) continue;
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

  /// Where [label] is printed in [row], spaces as printed. [fuzzy] also
  /// accepts a misread word close to it ("Fakturanummner").
  static Match? _findLabel(String row, String label, {String? fuzzy}) {
    final lower = row.toLowerCase();
    final exact = RegExp(label.split(' ').map(RegExp.escape).join(r'\s+')).firstMatch(lower);
    if (exact != null || fuzzy == null) return exact;
    return RegExp(r'[a-zåäö]{6,}')
        .allMatches(lower)
        .where((w) => TextPatterns.similarity(w[0]!, fuzzy) >= 0.8)
        .firstOrNull;
  }

  /// The value after a label on its row; for a label alone, the value at the
  /// start of the next row, or anywhere in it when it matches [below].
  Extracted<String> _labelledValue(List<TextRow> rows, List<String> norm, List<String> labels, RegExp value,
      {RegExp? below, String? fuzzy}) {
    for (var i = 0; i < rows.length; i++) {
      final n = norm[i];
      for (final l in [...labels, if (fuzzy != null) fuzzy]) {
        if (l == 'ocr' && (n.contains('ocr-nummer') || n.contains('ocr nr'))) continue;
        final at = _findLabel(rows[i].text, l, fuzzy: l == fuzzy ? fuzzy : null);
        if (at == null) continue;
        final after = rows[i].text.substring(at.end);
        final m = value.firstMatch(after.replaceFirst(RegExp(r'^[\s:.#]*'), ''));
        if (m != null && RegExp(r'\d').hasMatch(m.group(0)!)) {
          return Extracted(m.group(0)!, Confidence.high, source: rows[i].text);
        }
        if (i + 1 < rows.length) {
          final next = value.firstMatch(rows[i + 1].text.trim());
          if (next != null && next.start == 0 && RegExp(r'\d').hasMatch(next.group(0)!)) {
            return Extracted(next.group(0)!, Confidence.low, source: '${rows[i].text} / ${rows[i + 1].text}');
          }
          final anywhere = below?.firstMatch(rows[i + 1].text);
          if (anywhere != null) {
            return Extracted(anywhere.group(0)!, Confidence.low, source: '${rows[i].text} / ${rows[i + 1].text}');
          }
        }
      }
    }
    return const Extracted.none();
  }

  /// The OCR reference: five digits or more after an OCR label, never an
  /// amount ("17396,00") or a bankgiro check line ("1185#41#").
  Extracted<String> _ocrNumber(List<TextRow> rows, List<String> norm) {
    final value = RegExp(r'(?<![\d,.])\d(?: ?\d){4,24}(?![\d]|\s?[,.]\d|\s*#\d)');
    const labels = [
      'ocr-nummer', 'ocr nr', 'ocrnr', 'ocr', 'meddelande anges', 'referensnummer', 'fakturareferens',
    ];
    Extracted<String>? found;
    for (var i = 0; i < rows.length && found == null; i++) {
      final n = norm[i];
      for (final l in labels) {
        if (l == 'ocr' && (n.contains('ocr-nummer') || n.contains('ocr nr'))) continue;
        final at = _findLabel(rows[i].text, l);
        if (at == null) continue;
        final m = value.firstMatch(rows[i].text.substring(at.end));
        if (m != null) {
          found = Extracted(m[0]!, Confidence.high, source: rows[i].text);
          break;
        }
        // Alone on its row: the number one or two rows below; a long one there
        // need not be first ("grunden för …   526730297326").
        for (var j = i + 1; j <= i + 2 && j < rows.length; j++) {
          final next = value.firstMatch(rows[j].text);
          if (next == null) continue;
          final digits = next[0]!.replaceAll(' ', '').length;
          if ((j == i + 1 && next.start <= 1) || digits >= 10) {
            found = Extracted(next[0]!, Confidence.low, source: '${rows[i].text} / ${rows[j].text}');
            break;
          }
        }
        if (found != null) break;
      }
    }
    // The slip's code line: "# 4005628761 #".
    if (found == null) {
      for (final r in rows) {
        final m = RegExp(r'(?<!\d)(\d{5,25})\s*#\s').firstMatch(r.text);
        if (m != null) {
          found = Extracted(m[1]!, Confidence.low, source: r.text);
          break;
        }
      }
    }
    if (found == null) return const Extracted.none();
    var digits = found.value!.replaceAll(' ', '');
    // A digit cut off at the edge: the same number printed whole elsewhere.
    for (final r in rows) {
      for (final m in RegExp(r'\d{5,25}').allMatches(r.text.replaceAll(RegExp(r'(?<=\d) (?=\d)'), ''))) {
        final other = m[0]!;
        if (other.length > digits.length && other.length <= digits.length + 2 && other.startsWith(digits)) digits = other;
      }
    }
    return Extracted(digits, found.confidence, source: found.source);
  }
}

class _VatInfo {
  final List<InvoiceVatLine> lines;
  final (Money, String)? explicitTotal;
  final Money? net;
  final Money? grossSum;
  final bool fromTable;

  /// Set when an amount was reinterpreted, for the user to check.
  final String? note;
  const _VatInfo(this.lines, this.explicitTotal, this.net, this.grossSum, this.fromTable, {this.note});
}

class _Payment {
  final Money? cash;
  final Money? change;
  final Money? card;
  const _Payment(this.cash, this.change, this.card);
}
