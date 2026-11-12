import 'cost_types.dart';
import 'models.dart';
import 'money.dart';

/// One cost row of the resultatrapport.
class ResultCost {
  final String costType;
  final String label;
  final Money net;
  final int count;
  const ResultCost(this.costType, this.label, this.net, this.count);
}

/// A simple profit and loss for a period: sales and costs excl. VAT. Based
/// only on what is registered in the app; the accountant's books decide.
class ResultReport {
  final String title;
  final String fromIso;
  final String toIso;

  /// Cash register sales (Z-reports) excl. VAT.
  final Money cashSales;

  /// Online sales excl. the VAT printed on the partner's paper.
  final Money onlineSales;
  final List<ResultCost> costs;

  const ResultReport({
    required this.title,
    required this.fromIso,
    required this.toIso,
    required this.cashSales,
    required this.onlineSales,
    required this.costs,
  });

  Money get sales => cashSales + onlineSales;
  Money get totalCosts => Money.sum(costs.map((c) => c.net));
  Money get result => sales - totalCosts;

  /// Invoices with no cost type, to remind the user to choose one.
  int get unclassified => costs.where((c) => c.costType.isEmpty).fold(0, (n, c) => n + c.count);

  factory ResultReport.build({
    required String title,
    required String fromIso,
    required String toIso,
    required List<DailySales> sales,
    required List<Invoice> invoices,
    List<OnlineSale> online = const [],
  }) {
    bool inPeriod(String d) => d.compareTo(fromIso) >= 0 && d.compareTo(toIso) <= 0;
    final days = sales.where((s) => inPeriod(s.businessDate));
    final paid = online.where((o) => inPeriod(o.paymentDate));
    final bills = invoices.where((i) => inPeriod(i.bookingDate));
    final byType = <String, (Money, int)>{};
    for (final i in bills) {
      final key = CostType.byKey(i.costType) == null ? '' : i.costType;
      final prev = byType[key] ?? (Money.zero, 0);
      byType[key] = (prev.$1 + (i.total - i.vatTotal), prev.$2 + 1);
    }
    int order(String key) {
      final i = CostType.all.indexWhere((c) => c.key == key);
      return i < 0 ? CostType.all.length : i;
    }

    final keys = byType.keys.toList()..sort((a, b) => order(a).compareTo(order(b)));
    return ResultReport(
      title: title,
      fromIso: fromIso,
      toIso: toIso,
      cashSales: Money.sum(days.map((d) => d.detailedTotal - d.outputVat)),
      onlineSales: Money.sum(paid.map((o) => o.amount - o.vat)),
      costs: [for (final k in keys) ResultCost(k, CostType.labelFor(k), byType[k]!.$1, byType[k]!.$2)],
    );
  }
}
