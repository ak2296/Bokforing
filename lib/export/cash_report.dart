import '../domain/models.dart';
import '../domain/money.dart';
import 'table_export.dart';

/// "Kassarapport": per Z-report day the cash and card takings. Only days where the
/// report said something.
ReportTable cashReportTable(List<DailySales> sales, String title) {
  final days = [for (final d in sales) if (d.hasCashData) d]..sort((a, b) => a.businessDate.compareTo(b.businessDate));
  String m(Money? v) => v == null ? '' : v.format(unit: false);
  Money sum(Money? Function(DailySales) f) => Money.sum(days.map((d) => f(d) ?? Money.zero));
  return ReportTable(
    title: 'Kassarapport $title',
    fileName: 'kassarapport',
    headers: const ['Datum', 'Z-nr', 'Kontant (kr)', 'Kort och Swish (kr)'],
    rows: [for (final d in days) [d.businessDate, d.zNumber ?? '', m(d.cash), m(d.card)]],
    totals: ['Summa', '', m(sum((d) => d.cash)), m(sum((d) => d.card))],
  );
}
