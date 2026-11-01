import 'document_parser.dart';
import 'money.dart';
import 'ocr_models.dart';
import 'text_patterns.dart';

class OnlineDraft {
  final Extracted<String> date;
  final Extracted<String> partner;
  final Extracted<String> documentNumber;
  final Extracted<Money> amount;
  final List<String> notes;
  const OnlineDraft({
    required this.date,
    required this.partner,
    required this.documentNumber,
    required this.amount,
    required this.notes,
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

  @override
  OnlineDraft parse(OcrResult ocr) {
    final rows = ocr.rows();
    final norm = [for (final r in rows) TextPatterns.normalize(r.text)];
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
