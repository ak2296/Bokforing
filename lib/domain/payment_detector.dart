import 'text_patterns.dart';

enum PaymentKind { kvitto, faktura, unknown }

class PaymentDetection {
  final PaymentKind kind;

  /// True for a receipt, or for an invoice stamped as paid.
  final bool paid;
  final Confidence confidence;
  final List<String> reasons;
  const PaymentDetection(this.kind, this.paid, this.confidence, this.reasons);

  bool get isCertain => kind != PaymentKind.unknown && confidence == Confidence.high;
}

/// Tells a receipt (already paid) from an invoice to pay. Several signals
/// are weighed; the title alone ("Kvitto", "Faktura") never decides.
class PaymentDetector {
  const PaymentDetector();

  static const _receipt = <String, int>{
    'kvitto': 2,
    'kassakvitto': 3,
    'receipt': 2,
    'kontokort': 3,
    'kortbetalning': 3,
    'betalt med': 3,
    'betalat': 2,
    'kontant': 2,
    'swish': 2,
    'mottaget': 3,
    'erhållet': 3,
    'växel': 3,
    'godkänd': 2,
    'godkänt': 2,
    'terminal': 2,
    'kortnr': 2,
    '****': 2,
    'contactless': 2,
    'kontaktlös': 2,
    'kassör': 2,
    'kassa nr': 2,
    'öppet köp': 3,
    'spara kvittot': 3,
    'paid by': 3,
    'card': 1,
    'cash': 2,
    'change': 2,
  };

  static const _invoice = <String, int>{
    'faktura': 2,
    'fakturanummer': 3,
    'fakturanr': 3,
    'fakturadatum': 2,
    'förfallodatum': 4,
    'förfallodag': 4,
    'förfaller': 3,
    'betalas senast': 4,
    'bankgiro': 3,
    'plusgiro': 3,
    'ocr': 2,
    'betalningsvillkor': 3,
    'dröjsmålsränta': 3,
    'kundnummer': 1,
    'kundnr': 1,
    'invoice': 2,
    'due date': 4,
    'amount due': 3,
    'payment terms': 3,
  };

  /// [paperAspect] is height / width of the paper in the photo, when known.
  /// Thermal receipts are long and narrow; invoices are usually A4 (≈1.41).
  PaymentDetection detect(List<String> rows, {double? paperAspect}) {
    final norm = [for (final r in rows) TextPatterns.normalize(r)];
    final text = norm.join('\n');
    var receipt = 0, invoice = 0;
    final reasons = <String>[];
    for (final e in _receipt.entries) {
      if (text.contains(e.key)) {
        receipt += e.value;
        reasons.add(e.key);
      }
    }
    for (final e in _invoice.entries) {
      if (text.contains(e.key)) {
        invoice += e.value;
        reasons.add(e.key);
      }
    }
    // Time of purchase ("14:32") is typical for receipts.
    if (RegExp(r'\b\d{1,2}:\d{2}\b').hasMatch(text)) receipt += 1;
    if (paperAspect != null) {
      if (paperAspect >= 2.2) {
        receipt += 3;
        reasons.add('smalt kvittopapper');
      } else if (paperAspect >= 1.3 && paperAspect <= 1.55) {
        invoice += 2;
        reasons.add('A4-format');
      }
    }

    // A stamp "BETALD"/"BETALT" on its own line, or a credit note: nothing to pay.
    final stamped = norm.any((n) => RegExp(r'^(betald|betalt|paid)\b\W*$').hasMatch(n));
    final credit = text.contains('kreditnota') || text.contains('kreditfaktura') || text.contains('credit note');

    final margin = (receipt - invoice).abs();
    final kind = margin < 3
        ? PaymentKind.unknown
        : receipt > invoice
            ? PaymentKind.kvitto
            : PaymentKind.faktura;
    final paid = kind == PaymentKind.kvitto || stamped || credit;
    final confidence = stamped || credit
        ? Confidence.high
        : margin >= 5
            ? Confidence.high
            : margin >= 3
                ? Confidence.medium
                : Confidence.low;
    if (stamped) reasons.add('stämpel BETALD');
    return PaymentDetection(
        stamped && kind == PaymentKind.unknown ? PaymentKind.faktura : kind, paid, confidence, reasons);
  }
}
