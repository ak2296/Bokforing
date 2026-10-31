import 'text_patterns.dart';

enum DocumentType { invoice, zReport, unknown }

extension DocumentTypeText on DocumentType {
  String get label => switch (this) {
        DocumentType.invoice => 'Faktura',
        DocumentType.zReport => 'Z-rapport',
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
    final total = inv + z;
    if (total < 3) {
      return Classification(DocumentType.unknown, 0, inv, z, signals);
    }
    final type = inv >= z ? DocumentType.invoice : DocumentType.zReport;
    final winner = inv >= z ? inv : z;
    // Share of evidence, damped when there is little evidence overall.
    final share = winner / total;
    final strength = (winner / 10).clamp(0.0, 1.0);
    final confidence = share * (0.6 + 0.4 * strength);
    return Classification(type, confidence, inv, z, signals);
  }
}
