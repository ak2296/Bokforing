enum DocumentType { invoice, zReport, unknown }

class Classification {
  const Classification(this.type, this.confidence, this.invoiceScore, this.zScore);
  final DocumentType type;
  final double confidence;
  final int invoiceScore, zScore;

  /// Below this the user must choose the document type.
  bool get isCertain => type != DocumentType.unknown && confidence >= 0.7;
}

const _invoiceSignals = <List<Object>>[
  ['faktura', 3], ['fakturanummer', 3], ['ocr', 2], ['bankgiro', 2], ['plusgiro', 2],
  ['förfallodatum', 3], ['fakturadatum', 3], ['att betala', 3], ['betalningsvillkor', 2],
  ['org.?nr|organisationsnummer', 1], ['moms', 1], ['netto', 1],
];
const _zSignals = <List<Object>>[
  ['z-?rapport', 5], ['z-?nummer|z-?nr', 3], ['dagsrapport', 4],
  ['dagens försäljning|dagsförsäljning', 3], ['total försäljning', 2],
  ['betalningsmedel', 2], ['kontant', 1], ['swish', 1], ['varugrupp', 2],
  ['artiklar', 1], ['kassarapport|nollställning', 3], ['moms', 1],
];

int _score(String text, List<List<Object>> signals) {
  var s = 0;
  for (final sig in signals) {
    final re = RegExp('(?:^|[^a-zåäö])(?:${sig[0]})', caseSensitive: false);
    if (re.hasMatch(text)) s += sig[1] as int;
  }
  return s;
}

Classification classify(String text) {
  final f = _score(text, _invoiceSignals);
  final z = _score(text, _zSignals);
  final mx = f > z ? f : z;
  if (mx < 3) return Classification(DocumentType.unknown, 0, f, z);
  final conf = mx / (f + z) * (mx / 6 > 1 ? 1 : mx / 6);
  return Classification(f >= z ? DocumentType.invoice : DocumentType.zReport, conf, f, z);
}
