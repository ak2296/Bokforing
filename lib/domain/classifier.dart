import 'text_patterns.dart';

enum DocumentType { invoice, zReport, onlineSale, payslip, unknown }

extension DocumentTypeText on DocumentType {
  String get label => switch (this) {
        DocumentType.invoice => 'Faktura',
        DocumentType.zReport => 'Z-rapport',
        DocumentType.onlineSale => 'Onlineförsäljning',
        DocumentType.payslip => 'Lönebesked',
        DocumentType.unknown => 'Annat',
      };
}

class Classification {
  final DocumentType type;
  final double confidence;
  final double invoiceScore;
  final double zScore;
  final List<String> signals;
  const Classification(this.type, this.confidence, this.invoiceScore, this.zScore, this.signals);

  /// Below this the user must choose the type.
  static const threshold = 0.7;
  bool get isCertain => type != DocumentType.unknown && confidence >= threshold;
}

/// Weighted keyword scoring with several independent signals; no single
/// keyword decides the type.
class DocumentClassifier {
  const DocumentClassifier();

  static const _invoice = <String, double>{
    'faktura': 3,
    'fakturanummer': 4,
    'fakturanr': 4,
    'fakturadatum': 4,
    'förfallodatum': 4,
    'förfallodag': 4,
    'att betala': 3,
    'bankgiro': 3,
    'bg ': 1,
    'plusgiro': 3,
    'ocr': 2,
    'betalningsvillkor': 3,
    'dröjsmålsränta': 2,
    'kundnr': 2,
    'kundnummer': 2,
    'netto': 1,
    'exkl': 1,
    'kvitto': 2,
    'kvittonr': 2,
    'org.nr': 1,
    'orgnr': 1,
    'momspliktigt': 2,
    'kontokort': 1,
    'mottaget': 1,
    'växel': 1,
    'kvittokopia': 2,
    'invoice': 3,
    'receipt': 3,
    'amount due': 3,
    'due date': 3,
    'bill to': 2,
    'payment terms': 3,
    'subtotal': 1,
    'vat': 1,
  };

  static const _z = <String, double>{
    'z-rapport': 6,
    'zrapport': 6,
    'z rapport': 5,
    'z-nr': 4,
    'z-nummer': 4,
    'dagsrapport': 5,
    'dagens försäljning': 4,
    'total försäljning': 3,
    'periodens försäljning': 4,
    'försäljning per': 3,
    'varugrupp': 4,
    'artikelgrupp': 3,
    'betalningsmedel': 3,
    'betalningar': 2,
    'kontant': 1,
    'swish': 1,
    'antal kvitton': 3,
    'kvitton': 1,
    'grand total': 3,
    'kassalåda': 3,
    'växelkassa': 3,
    'momsgrupp': 3,
    'returer': 2,
    'x-rapport': 3,
    'kassarapport': 4,
    'z-report': 6,
    'z report': 5,
    'daily report': 4,
    'end of day': 4,
    'total sales': 3,
  };

  /// A lönebesked, also called lönespecifikation. Compound words only (a bare
  /// "lön" is in too many places), each also without å/ä/ö because the
  /// camera text often drops them. "Utbetalningsdatum" is left out: partner
  /// payout papers print it too.
  static const _payslip = <String, double>{
    'lönebesked': 7,
    'lonebesked': 7,
    'lönespecifikation': 7,
    'lonespecifikation': 7,
    'lönespec': 5,
    'lonespec': 5,
    'lönekvitto': 5,
    'lonekvitto': 5,
    'bruttolön': 4,
    'bruttolon': 4,
    'nettolön': 3,
    'nettolon': 3,
    'arbetsgivaravgift': 4,
    'preliminär skatt': 3,
    'preliminar skatt': 3,
    'preliminärskatt': 3,
    'skatteavdrag': 2,
    'löneperiod': 4,
    'loneperiod': 4,
    'löneart': 3,
    'loneart': 3,
    'anställningsnummer': 3,
    'anstallningsnummer': 3,
    'payslip': 6,
    'salary slip': 5,
    'gross pay': 3,
    'net pay': 3,
  };

  Classification classify(String text) {
    final t = TextPatterns.normalize(text);
    if (t.length < 15) {
      return const Classification(DocumentType.unknown, 0, 0, 0, ['För lite text']);
    }
    final signals = <String>[];
    double score(Map<String, double> words) {
      var s = 0.0;
      for (final e in words.entries) {
        if (t.contains(e.key)) {
          s += e.value;
          signals.add(e.key.trim());
        }
      }
      return s;
    }

    final inv = score(_invoice);
    final z = score(_z);
    final pay = score(_payslip);
    final total = inv + z + pay;
    if (total < 3) {
      return Classification(DocumentType.unknown, 0, inv, z, signals);
    }
    // A payslip must clearly beat both others; without payslip words the
    // choice is the same as before.
    final isPayslip = pay > inv && pay > z;
    final type = isPayslip
        ? DocumentType.payslip
        : inv >= z
            ? DocumentType.invoice
            : DocumentType.zReport;
    final winner = isPayslip ? pay : (inv >= z ? inv : z);
    // Share of evidence, damped when there is little evidence overall.
    final share = winner / total;
    final strength = (winner / 10).clamp(0.0, 1.0);
    final confidence = share * (0.6 + 0.4 * strength);
    return Classification(type, confidence, inv, z, signals);
  }
}
