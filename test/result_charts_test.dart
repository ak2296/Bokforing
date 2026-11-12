import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/result_report.dart';
import 'package:bokforing/ui/widgets/result_charts.dart';
import 'package:flutter_test/flutter_test.dart';

ResultReport _report(int cash, List<(String, int)> costs) => ResultReport(
      title: 'Oktober 2026',
      fromIso: '2026-10-01',
      toIso: '2026-10-31',
      cashSales: Money.kr(cash),
      onlineSales: Money.zero,
      costs: [for (final c in costs) ResultCost(c.$1, c.$1, Money.kr(c.$2), 1)],
    );

void main() {
  test('the waterfall runs from intäkter down to the result', () {
    final steps = waterfallSteps(_report(1000, [('varuinkop', 300), ('hyra', 200)]));
    expect(steps.map((s) => s.label), ['Intäkter', 'varuinkop', 'hyra', 'Resultat']);
    expect([steps[1].start, steps[1].end], [700, 1000]);
    expect([steps[2].start, steps[2].end], [500, 700]);
    expect([steps.last.start, steps.last.end], [0, 500]);
  });

  test('more than five cost types: the rest are added up', () {
    final steps = waterfallSteps(_report(1000, [for (var i = 0; i < 7; i++) ('k$i', 10 + i)]));
    expect(steps.length, 1 + 5 + 1 + 1);
    expect(steps[steps.length - 2].label, 'Övriga kostnader');
    expect(steps[steps.length - 2].amount, Money.kr(-(10 + 11)));
  });

  test('costs above the sales give a negative result', () {
    final steps = waterfallSteps(_report(100, [('varuinkop', 250)]));
    expect(steps.last.amount, Money.kr(-150));
    expect([steps.last.start, steps.last.end], [-150, 0]);
  });
}
