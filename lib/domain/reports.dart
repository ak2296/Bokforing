import 'dates.dart';
import 'models.dart';
import 'money.dart';

/// A column in the monthly table. Columns follow the user's categories;
/// a deleted category still gets a column if that month has data for it.
class ReportColumn {
  final int? categoryId;
  final String name;
  const ReportColumn(this.categoryId, this.name);

  String get key => categoryId != null ? 'id:$categoryId' : 'name:$name';
}

class MonthlyRow {
  final String date;
  final Map<String, Money> amounts;
  final Money sales;
  final Money outputVat;
  final Money expenses;
  final Money inputVat;
  final int invoiceCount;
  final int zReportCount;
  final bool hasSalesDifference;

  const MonthlyRow({
    required this.date,
    required this.amounts,
    required this.sales,
    required this.outputVat,
    required this.expenses,
    required this.inputVat,
    required this.invoiceCount,
    required this.zReportCount,
    required this.hasSalesDifference,
  });
}

class MonthlyReport {
  final int year;
  final int month;
  final List<ReportColumn> columns;
  final List<MonthlyRow> rows;
  final Map<String, Money> columnTotals;
  final Money totalSales;
  final Money totalExpenses;
  final Money totalOutputVat;
  final Money totalInputVat;

  const MonthlyReport({
    required this.year,
    required this.month,
    required this.columns,
    required this.rows,
    required this.columnTotals,
    required this.totalSales,
    required this.totalExpenses,
    required this.totalOutputVat,
    required this.totalInputVat,
  });

  /// Utgående moms − ingående moms. Positive: to pay; negative: to get back.
  Money get vatDifference => totalOutputVat - totalInputVat;

  String get title => SwedishDates.monthTitle(year, month);
}

class YearRow {
  final int month;
  final Money sales;
  final Money expenses;
  final Money outputVat;
  final Money inputVat;
  const YearRow(this.month, this.sales, this.expenses, this.outputVat, this.inputVat);
  Money get vatDifference => outputVat - inputVat;
  String get monthName => SwedishDates.capitalize(SwedishDates.months[month - 1]);
}

class YearReport {
  final int year;
  final List<YearRow> rows;
  const YearReport(this.year, this.rows);

  Money get sales => Money.sum(rows.map((r) => r.sales));
  Money get expenses => Money.sum(rows.map((r) => r.expenses));
  Money get outputVat => Money.sum(rows.map((r) => r.outputVat));
  Money get inputVat => Money.sum(rows.map((r) => r.inputVat));
  Money get vatDifference => outputVat - inputVat;
}

/// Builds reports from source records. Totals are always derived here and
/// never stored, so they cannot drift from the underlying data.
class ReportGenerator {
  const ReportGenerator();

  MonthlyReport monthly({
    required int year,
    required int month,
    required List<Category> categories,
    required List<DailySales> sales,
    required List<Invoice> invoices,
  }) {
    final prefix = '${SwedishDates.monthKey(year, month)}-';
    final monthSales = sales.where((s) => s.businessDate.startsWith(prefix)).toList();
    final monthInvoices = invoices.where((i) => i.invoiceDate.startsWith(prefix)).toList();

    final active = categories.where((c) => c.active).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final columns = <ReportColumn>[for (final c in active) ReportColumn(c.id, c.name)];
    final known = {for (final c in columns) c.key};
    final byId = {for (final c in categories) if (c.id != null) c.id!: c};
    for (final day in monthSales) {
      for (final item in day.items) {
        final col = _columnFor(item, byId);
        if (known.add(col.key)) columns.add(col);
      }
    }

    final dates = <String>{
      ...monthSales.map((s) => s.businessDate),
      ...monthInvoices.map((i) => i.invoiceDate),
    }.toList()
      ..sort();

    final rows = <MonthlyRow>[];
    final columnTotals = <String, Money>{for (final c in columns) c.key: Money.zero};
    for (final date in dates) {
      final daySales = monthSales.where((s) => s.businessDate == date).toList();
      final dayInvoices = monthInvoices.where((i) => i.invoiceDate == date).toList();
      final amounts = <String, Money>{};
      for (final day in daySales) {
        for (final item in day.items) {
          final key = _columnFor(item, byId).key;
          amounts[key] = (amounts[key] ?? Money.zero) + item.amount;
          columnTotals[key] = (columnTotals[key] ?? Money.zero) + item.amount;
        }
      }
      rows.add(MonthlyRow(
        date: date,
        amounts: amounts,
        sales: Money.sum(daySales.map((d) => d.detailedTotal)),
        outputVat: Money.sum(daySales.map((d) => d.outputVat)),
        expenses: Money.sum(dayInvoices.map((i) => i.total)),
        inputVat: Money.sum(dayInvoices.map((i) => i.vatTotal)),
        invoiceCount: dayInvoices.length,
        zReportCount: daySales.length,
        hasSalesDifference: daySales.any((d) => !d.difference.isZero),
      ));
    }

    return MonthlyReport(
      year: year,
      month: month,
      columns: columns,
      rows: rows,
      columnTotals: columnTotals,
      totalSales: Money.sum(rows.map((r) => r.sales)),
      totalExpenses: Money.sum(rows.map((r) => r.expenses)),
      totalOutputVat: Money.sum(rows.map((r) => r.outputVat)),
      totalInputVat: Money.sum(rows.map((r) => r.inputVat)),
    );
  }

  YearReport yearly({
    required int year,
    required List<DailySales> sales,
    required List<Invoice> invoices,
  }) {
    final rows = <YearRow>[];
    for (var m = 1; m <= 12; m++) {
      final prefix = '${SwedishDates.monthKey(year, m)}-';
      final s = sales.where((d) => d.businessDate.startsWith(prefix));
      final i = invoices.where((d) => d.invoiceDate.startsWith(prefix));
      rows.add(YearRow(
        m,
        Money.sum(s.map((d) => d.detailedTotal)),
        Money.sum(i.map((d) => d.total)),
        Money.sum(s.map((d) => d.outputVat)),
        Money.sum(i.map((d) => d.vatTotal)),
      ));
    }
    return YearReport(year, rows);
  }

  ReportColumn _columnFor(SalesItem item, Map<int, Category> byId) {
    final id = item.categoryId;
    if (id != null && byId.containsKey(id)) {
      final c = byId[id]!;
      return ReportColumn(id, c.active ? c.name : item.categoryName);
    }
    return ReportColumn(null, item.categoryName);
  }
}
