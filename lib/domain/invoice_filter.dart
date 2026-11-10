import 'cost_types.dart';
import 'models.dart';

/// The search on Utgifter: free text plus supplier, cost type and date range.
class InvoiceFilter {
  /// Matched against supplier, invoice number, OCR number and cost type name.
  final String query;

  /// Exact supplier name, case-insensitive; null for every supplier.
  final String? supplier;

  /// [CostType.key]; '' for invoices without a cost type; null for all.
  final String? costType;

  /// Inclusive ISO dates; null for an open end.
  final String? from;
  final String? to;

  const InvoiceFilter({this.query = '', this.supplier, this.costType, this.from, this.to});

  bool get active =>
      query.trim().isNotEmpty || supplier != null || costType != null || from != null || to != null;

  bool matches(Invoice i) {
    if (supplier != null && i.supplier.trim().toLowerCase() != supplier!.trim().toLowerCase()) return false;
    if (costType != null && i.costType != costType) return false;
    if (from != null && i.invoiceDate.compareTo(from!) < 0) return false;
    if (to != null && i.invoiceDate.compareTo(to!) > 0) return false;
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return true;
    final text = [
      i.supplier,
      i.invoiceNumber,
      i.ocrReference,
      CostType.byKey(i.costType)?.label ?? '',
    ].join(' ').toLowerCase();
    return words.every(text.contains);
  }

  InvoiceFilter copyWith({
    String? query,
    String? supplier,
    String? costType,
    String? from,
    String? to,
    bool clearSupplier = false,
    bool clearCostType = false,
    bool clearDates = false,
  }) =>
      InvoiceFilter(
        query: query ?? this.query,
        supplier: clearSupplier ? null : (supplier ?? this.supplier),
        costType: clearCostType ? null : (costType ?? this.costType),
        from: clearDates ? null : (from ?? this.from),
        to: clearDates ? null : (to ?? this.to),
      );
}
