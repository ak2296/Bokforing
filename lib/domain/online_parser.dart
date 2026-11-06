import 'document_parser.dart';
import 'invoice_parser.dart';
import 'models.dart';
import 'money.dart';
import 'ocr_models.dart';
import 'payment_detector.dart';
import 'text_patterns.dart';
import 'vat.dart';

class OnlineDraft {
  final Extracted<String> date;
  final Extracted<String> partner;
  final Extracted<String> documentNumber;
  final Extracted<Money> amount;

  /// Output VAT printed on a självfaktura; none for a plain payout.
  final Extracted<Money> vat;
  final VatRate? vatRate;

  /// The partner's own invoice printed on the same paper, reviewed next.
  final InvoiceDraft? feesInvoice;
  final List<String> notes;
  const OnlineDraft({
    required this.date,
    required this.partner,
    required this.documentNumber,
    required this.amount,
    required this.notes,
    this.vat = const Extracted.none(),
    this.vatRate,
    this.feesInvoice,
  });
}

/// Reads a partner's payment confirmation: the payment date decides the
/// month, the paid amount adds to the month's online sales.
class OnlineParser implements DocumentParser<OnlineDraft> {
  /// Partner names already used, matched ignoring spaces.
  final List<String> knownPartners;
  const OnlineParser({this.knownPartners = const []});

  static const _amountLabels = <String, int>{
    'betalt belopp': 100,
    'belopp betalt': 100,
    'utbetalt belopp': 100,
    'utbetalt': 90,
    'att utbetala': 90,
    'utbetalning': 70,
    'amount paid': 100,
    'total payout': 100,
    'payout': 70,
    'totalt belopp': 60,
    'totalt': 40,
    'total': 30,
  };
  static const _dateLabels = [
    'betalningsdatum', 'betalningdatum', 'betaldatum', 'utbetalningsdatum', 'utbetald', 'payment date', 'payout date',
  ];
  static const _numberLabels = ['dokumentnummer', 'dokumentnr', 'betalningsnummer', 'referens', 'document number'];
  static const _commonPartners = ['foodora', 'wolt', 'uber eats', 'ubereats', 'bolt food', 'onlinepizza', 'just eat'];

  /// Words typical for a partner's payout paper.
  static bool looksLikeOnline(String text, {List<String> partners = const []}) {
    final n = TextPatterns.normalize(text);
    if (n.contains('betalningsbekräftelse') || n.contains('utförda betalningar')) return true;
    return [..._commonPartners, ...partners.map((p) => p.toLowerCase())]
        .any((p) => p.length >= 4 && n.contains(p) && n.contains('betalt belopp'));
  }

  /// A självfaktura for your sales (1) and the partner's invoice for its fees
  /// (2) on one paper, as Foodora sends.
  static bool isCombined(String text) {
    final n = TextPatterns.normalize(text);
    return (n.contains('självfaktura') || n.contains('sjalvfaktura')) && n.contains('totalt (2)');
  }

  @override
  OnlineDraft parse(OcrResult ocr) {
    final rows = ocr.rows();
    final norm = [for (final r in rows) TextPatterns.normalize(r.text)];
    if (isCombined(norm.join('\n'))) {
      final combined = _combined(rows, norm);
      if (combined != null) return combined;
    }
    final notes = <String>[];

    Extracted<Money> amount = const Extracted.none();
    var best = 0;
    for (var i = 0; i < rows.length; i++) {
      for (final e in _amountLabels.entries) {
        if (!norm[i].contains(e.key) || e.value <= best) continue;
        var a = TextPatterns.amounts(rows[i].text);
        if (a.isEmpty && i + 1 < rows.length) a = TextPatterns.amounts(rows[i + 1].text);
        if (a.isEmpty || a.last.value.isZero) continue;
        best = e.value;
        amount = Extracted(a.last.value, best >= 90 ? Confidence.high : Confidence.medium, source: rows[i].text);
      }
    }
    if (!amount.hasValue) notes.add('Betalt belopp hittades inte. Fyll i beloppet.');

    Extracted<String> date = const Extracted.none();
    for (var i = 0; i < rows.length && !date.hasValue; i++) {
      if (!_dateLabels.any(norm[i].contains)) continue;
      var d = TextPatterns.dates(rows[i].text);
      if (d.isEmpty && i + 1 < rows.length) d = TextPatterns.dates(rows[i + 1].text);
      if (d.isNotEmpty) date = Extracted(d.first, Confidence.high, source: rows[i].text);
    }
    if (!date.hasValue) notes.add('Betalningsdatum hittades inte. Datumet avgör vilken månad beloppet räknas till.');

    return OnlineDraft(
      date: date,
      partner: _partner(rows, norm),
      documentNumber: _number(rows, norm),
      amount: amount,
      notes: notes,
    );
  }

  /// Last amount on the row with [label] in [from]..[to], or on the next row
  /// when the label stands alone.
  static Money? _labelled(List<TextRow> rows, List<String> norm, int from, int to, bool Function(String) label) {
    for (var i = from; i < to; i++) {
      if (!label(norm[i])) continue;
      var a = TextPatterns.amounts(rows[i].text);
      if (a.isEmpty && i + 1 < rows.length) a = TextPatterns.amounts(rows[i + 1].text);
      if (a.isNotEmpty) return a.last.value.abs();
    }
    return null;
  }

  /// The VAT row in [from]..[to]: the amount that is the rate of [net], or
  /// the last amount on the row.
  static (Money, VatRate)? _vatRow(List<TextRow> rows, List<String> norm, int from, int to, Money? net) {
    for (var i = from; i < to; i++) {
      if (!norm[i].contains('moms') || norm[i].contains('exkl')) continue;
      final rate = TextPatterns.rate(rows[i].text);
      if (rate == null || !const [VatRate.six, VatRate.twelve, VatRate.twentyFive].contains(rate)) continue;
      final amounts = [
        ...TextPatterns.amounts(rows[i].text),
        if (i + 1 < rows.length) ...TextPatterns.amounts(rows[i + 1].text),
      ].map((t) => t.value.abs()).toList();
      if (amounts.isEmpty) continue;
      if (net != null) {
        final expected = VatCalculator.vatFromNet(net, rate);
        final fit = amounts.where((v) => (v - expected).abs() <= const Money(3)).firstOrNull;
        if (fit != null) return (fit, rate);
      }
      return (TextPatterns.amounts(rows[i].text).lastOrNull?.value.abs() ?? amounts.first, rate);
    }
    return null;
  }

  /// Splits the paper at "Totalt (1)": above it your sales, below it the
  /// partner's fees. Amounts are shown as positive; the fees are a cost.
  OnlineDraft? _combined(List<TextRow> rows, List<String> norm) {
    final split = norm.indexWhere((n) => n.contains('totalt (1)'));
    if (split < 0) return null;
    final end = rows.length;
    final total1 = _labelled(rows, norm, split, split + 1, (n) => true);
    final net1 = _labelled(rows, norm, 0, split, (n) => n.contains('exkl'));
    final vat1 = _vatRow(rows, norm, 0, split, net1);
    final total2 = _labelled(rows, norm, split + 1, end, (n) => n.contains('totalt (2)'));
    final net2 = _labelled(rows, norm, split + 1, end, (n) => n.contains('exkl'));
    final vat2 = _vatRow(rows, norm, split + 1, end, net2);
    if (total1 == null || total2 == null) return null;

    String? dateAfter(bool Function(String) label) {
      for (var i = 0; i < rows.length; i++) {
        if (!label(norm[i])) continue;
        final d = TextPatterns.dates(rows[i].text);
        if (d.isNotEmpty) return d.first;
      }
      return null;
    }

    final date = dateAfter((n) => n.startsWith('datum') || n.startsWith('fakturadatum'));
    final due = dateAfter((n) => n.contains('förfallodatum'));
    bool adds(Money? net, (Money, VatRate)? vat, Money total) =>
        net != null && vat != null && (net + vat.$1 - total).abs() < Money.ignoredDifference;
    Confidence sure(bool ok) => ok ? Confidence.high : Confidence.medium;
    final ok1 = adds(net1, vat1, total1);
    final ok2 = adds(net2, vat2, total2);

    String? number;
    for (var i = split + 1; i < end && number == null; i++) {
      number = RegExp(r'faktura\s+(\d[\d-]*\d)', caseSensitive: false).firstMatch(rows[i].text)?.group(1);
    }
    final supplier = rows.map((r) => r.text.trim()).where((t) => RegExp(r'\bAB\b').hasMatch(t)).firstOrNull;
    final payable = _labelled(rows, norm, split + 1, end, (n) => n.contains('att betala'));

    final fees = InvoiceDraft(
      date: date == null ? const Extracted.none() : Extracted(date, Confidence.high),
      dueDate: due == null ? const Extracted.none() : Extracted(due, Confidence.high),
      supplier: supplier == null ? const Extracted.none() : Extracted(supplier, Confidence.medium),
      invoiceNumber: number == null ? const Extracted.none() : Extracted(number, Confidence.high),
      ocrReference: const Extracted.none(),
      total: Extracted(total2, sure(ok2)),
      vatTotal: vat2 == null ? const Extracted.none() : Extracted(vat2.$1, sure(ok2)),
      vatCalculated: false,
      vatLines: [if (vat2 != null) InvoiceVatLine(rate: vat2.$2, vat: vat2.$1, net: net2, gross: total2)],
      net: net2,
      totalCandidates: const [],
      payment: const PaymentDetection(PaymentKind.faktura, false, Confidence.low, []),
      notes: [
        'Partnerns avgifter från samma papper som din försäljning.',
        if (payable != null)
          'Att betala enligt pappret efter avräkning mot din försäljning: ${payable.format()}. Välj om det redan är betalt.',
      ],
    );

    return OnlineDraft(
      date: date == null ? const Extracted.none() : Extracted(date, Confidence.high),
      partner: _partner(rows, norm),
      documentNumber: _number(rows, norm),
      amount: Extracted(total1, sure(ok1)),
      vat: vat1 == null ? const Extracted.none() : Extracted(vat1.$1, sure(ok1)),
      vatRate: vat1?.$2,
      feesInvoice: fees,
      notes: const ['Pappret har två delar: först din försäljning, sedan partnerns faktura för avgifterna.'],
    );
  }

  Extracted<String> _partner(List<TextRow> rows, List<String> norm) {
    String squeeze(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9åäö]'), '');
    final text = squeeze(rows.map((r) => r.text).join(' '));
    for (final p in knownPartners) {
      if (squeeze(p).length >= 3 && text.contains(squeeze(p))) return Extracted(p, Confidence.high);
    }
    for (final p in _commonPartners) {
      if (text.contains(squeeze(p))) {
        final name = p.split(' ').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
        return Extracted(name, Confidence.high);
      }
    }
    return const Extracted.none();
  }

  Extracted<String> _number(List<TextRow> rows, List<String> norm) {
    for (var i = 0; i < rows.length; i++) {
      for (final l in _numberLabels) {
        final idx = norm[i].indexOf(l);
        if (idx < 0) continue;
        final m = RegExp(r'[A-Za-z0-9][A-Za-z0-9-]{3,}').firstMatch(norm[i].substring(idx + l.length));
        if (m != null) return Extracted(m.group(0)!, Confidence.high, source: rows[i].text);
      }
    }
    return const Extracted.none();
  }
}
