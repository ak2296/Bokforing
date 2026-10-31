import '../domain/classifier.dart';
import '../domain/dates.dart';
import '../domain/invoice_parser.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/ocr_models.dart';
import '../domain/text_patterns.dart';
import '../domain/vat.dart';
import '../domain/z_report_parser.dart';

/// What the online model suggested. Amounts are kept as the printed text and
/// converted here with the same deterministic parser as the offline reader;
/// the model never does the arithmetic.
class AiResult {
  final DocumentType type;
  final String? date;
  final String? supplier;
  final String? invoiceNumber;
  final String? ocrReference;
  final String? dueDate;
  final String? totalText;
  final String? vatTotalText;
  final List<({String? rate, String? vat, String? net, String? gross})> vatLines;
  final String? zNumber;
  final List<({String label, String amount})> zRows;
  final String? notes;

  const AiResult({
    required this.type,
    this.date,
    this.supplier,
    this.invoiceNumber,
    this.ocrReference,
    this.dueDate,
    this.totalText,
    this.vatTotalText,
    this.vatLines = const [],
    this.zNumber,
    this.zRows = const [],
    this.notes,
  });

  static String? _s(Object? v) {
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty || s.toLowerCase() == 'null' ? null : s;
  }

  factory AiResult.fromJson(Map<String, dynamic> j) {
    final type = switch (_s(j['document_type'])) {
      'faktura' => DocumentType.invoice,
      'z_rapport' => DocumentType.zReport,
      _ => DocumentType.unknown,
    };
    return AiResult(
      type: type,
      date: _s(j['date']),
      supplier: _s(j['supplier']),
      invoiceNumber: _s(j['invoice_number']),
      ocrReference: _s(j['ocr_reference']),
      dueDate: _s(j['due_date']),
      totalText: _s(j['total_text']),
      vatTotalText: _s(j['vat_total_text']),
      vatLines: [
        for (final l in (j['vat_lines'] as List? ?? const []))
          if (l is Map)
            (rate: _s(l['rate_percent']), vat: _s(l['vat_text']), net: _s(l['net_text']), gross: _s(l['gross_text'])),
      ],
      zNumber: _s(j['z_number']),
      zRows: [
        for (final r in (j['z_rows'] as List? ?? const []))
          if (r is Map && _s(r['label']) != null && _s(r['amount_text']) != null)
            (label: _s(r['label'])!, amount: _s(r['amount_text'])!),
      ],
      notes: _s(j['notes']),
    );
  }

  static const aiNote = 'Förslag från förbättrad analys online. Kontrollera varje värde mot dokumentet.';

  String? _date(String? s) => s != null && SwedishDates.isValidIso(s) ? s : null;

  InvoiceDraft toInvoiceDraft() {
    final notes = <String>[aiNote];
    final total = totalText == null ? null : Money.parse(totalText!);
    if (totalText != null && total == null) notes.add('Summan "$totalText" kunde inte tolkas som ett belopp.');
    final lines = <InvoiceVatLine>[];
    for (final l in vatLines) {
      final rate = l.rate == null ? null : VatRate.parse(l.rate!.replaceAll('%', ''));
      final vat = l.vat == null ? null : Money.parse(l.vat!);
      if (rate == null || vat == null) continue;
      if (vat.isZero) continue;
      lines.add(InvoiceVatLine(
        rate: rate,
        vat: vat,
        net: l.net == null ? null : Money.parse(l.net!),
        gross: l.gross == null ? null : Money.parse(l.gross!),
      ));
    }
    final explicitVat = vatTotalText == null ? null : Money.parse(vatTotalText!);
    final vatTotal = explicitVat ?? (lines.isEmpty ? null : Money.sum(lines.map((l) => l.vat)));
    final nets = lines.map((l) => l.net).toList();
    if (notes.length == 1 && this.notes != null) notes.add('Kommentar: ${this.notes}');
    Extracted<T> ex<T>(T? v) => v == null ? Extracted<T>.none() : Extracted<T>(v, Confidence.medium, note: 'Förbättrad analys');
    return InvoiceDraft(
      date: ex(_date(date)),
      dueDate: ex(_date(dueDate)),
      supplier: ex(supplier),
      invoiceNumber: ex(invoiceNumber),
      ocrReference: ex(ocrReference?.replaceAll(RegExp(r'\s'), '')),
      total: ex(total),
      vatTotal: ex(vatTotal),
      vatCalculated: false,
      vatLines: lines,
      net: lines.isNotEmpty && nets.every((n) => n != null) ? Money.sum(nets.cast<Money>()) : null,
      totalCandidates: const [],
      notes: notes,
    );
  }

  /// Z-rows are matched to the user's categories with the same cautious
  /// rules as the offline reader (exact or remembered names only).
  ZReportDraft toZReportDraft(List<Category> categories, Map<String, int> aliases, {Set<String> ignored = const {}}) {
    final buf = StringBuffer('Z-rapport\n');
    if (totalText != null) buf.writeln('Total försäljning $totalText');
    buf.writeln('Försäljning per varugrupp');
    for (final r in zRows) {
      buf.writeln('${r.label}   ${r.amount}');
    }
    final parsed = ZReportParser(categories, aliases: aliases, ignored: ignored).parse(OcrResult.fromPlainText(buf.toString()));
    final d = _date(date);
    return ZReportDraft(
      date: d == null ? const Extracted.none() : Extracted(d, Confidence.medium, note: 'Förbättrad analys'),
      otherDates: const [],
      zNumber: zNumber == null ? const Extracted.none() : Extracted(zNumber!, Confidence.medium),
      total: parsed.total.hasValue ? Extracted(parsed.total.value!, Confidence.medium) : const Extracted.none(),
      lines: parsed.lines,
      sectionFound: true,
      notes: [aiNote, if (notes != null) 'Kommentar: $notes'],
    );
  }
}
