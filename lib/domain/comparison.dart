import 'money.dart';
import 'reports.dart';

/// What the Jämför view compares.
enum CompareMetric {
  sales('Försäljning'),
  expenses('Utgifter'),
  vat('Moms att betala');

  final String label;
  const CompareMetric(this.label);

  Money of(YearRow r) => switch (this) {
        CompareMetric.sales => r.sales,
        CompareMetric.expenses => r.expenses,
        CompareMetric.vat => r.vatDifference,
      };
}

/// One month of year [a] against the same month of year [b].
class CompareRow {
  final int month;
  final Money a;
  final Money b;
  const CompareRow(this.month, this.a, this.b);

  /// Change from [b] to [a] in percent, or null when [b] is zero.
  double? get changePercent => b.isZero ? null : (a.ore - b.ore) * 100 / b.ore.abs();
}

class Comparison {
  final int yearA;
  final int yearB;
  final CompareMetric metric;
  final List<CompareRow> rows;
  const Comparison(this.yearA, this.yearB, this.metric, this.rows);

  factory Comparison.of(YearReport a, YearReport b, CompareMetric metric) => Comparison(a.year, b.year, metric, [
        for (var m = 1; m <= 12; m++) CompareRow(m, metric.of(a.rows[m - 1]), metric.of(b.rows[m - 1])),
      ]);

  Money get totalA => Money.sum(rows.map((r) => r.a));
  Money get totalB => Money.sum(rows.map((r) => r.b));
  CompareRow get total => CompareRow(0, totalA, totalB);
}

/// "+8 %", "−2 %" or "–" when there is nothing to compare with.
String formatChange(double? percent) {
  if (percent == null) return '–';
  final rounded = percent.round();
  if (rounded == 0) return '0 %';
  return rounded > 0 ? '+$rounded %' : '−${rounded.abs()} %';
}
