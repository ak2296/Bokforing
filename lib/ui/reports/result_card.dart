import 'package:flutter/material.dart';

import '../../domain/money.dart';
import '../../domain/result_report.dart';
import '../../domain/tax_estimate.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Resultat for a month or a year: sales minus costs, both without moms, then
/// the estimated tax to set aside and what is left. For a year, the moms to
/// pay is shown too.
class ResultSummaryCard extends StatelessWidget {
  final String title;
  final String from;
  final String to;

  /// Months of 12 counted for an owner's yearly amount: 1 for a month, 12 for a year.
  final int months;

  /// The year's moms difference; null leaves the moms lines out.
  final Money? vat;
  const ResultSummaryCard({super.key, required this.title, required this.from, required this.to, this.months = 1, this.vat});

  Widget _row(String label, Money v, {bool strong = false, Color? color}) {
    final style = strong ? moneyStyle.copyWith(fontWeight: FontWeight.bold, color: color) : moneyStyle.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: strong ? const TextStyle(fontWeight: FontWeight.bold) : null)),
        Text(v.format(), style: style),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Reloading<(ResultReport, TaxEstimate)>(
        deps: '$from$to',
        loader: (c) async {
          final report = ResultReport.build(
            title: title,
            fromIso: from,
            toIso: to,
            sales: await c.repo.dailySalesBetween(from, to),
            invoices: await c.repo.invoicesForReports(from, to),
            online: await c.repo.onlineSalesBetween(from, to),
          );
          return (report, await c.repo.taxEstimate());
        },
        builder: (context, data) {
          final (r, tax) = data;
          final t = Theme.of(context).textTheme;
          final owed = tax.tax(r.result, months: months);
          final after = owed == null ? null : r.result - owed;
          final good = r.result.isNegative ? AppTheme.danger : AppTheme.seed;
          final v = vat;
          return Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(title, style: t.titleSmall),
                const SizedBox(height: 6),
                _row('Försäljning exkl. moms', r.sales),
                _row('Utgifter exkl. moms', -r.totalCosts),
                const Divider(),
                _row('Resultat före skatt', r.result, strong: true, color: owed == null ? good : null),
                if (owed != null) ...[
                  _row(tax.label, -owed),
                  const Divider(),
                  _row('Resultat efter skatt', after!, strong: true, color: after.isNegative ? AppTheme.danger : AppTheme.seed),
                  const SizedBox(height: 4),
                  Text(tax.note, style: t.bodySmall),
                ],
                if (v != null) ...[
                  const Divider(),
                  _row('Utgående moms − ingående moms', v),
                  _row(v.isNegative ? 'Moms att få tillbaka för året' : 'Moms att betala för året', v.abs(), strong: true),
                ],
              ]),
            ),
          );
        },
      );
}
