import 'package:flutter/material.dart';

import '../../domain/money.dart';
import '../../domain/result_report.dart';
import '../theme.dart';
import 'charts.dart';

/// One step of the waterfall: a bar from [from] to [to] (kr), at [offset].
class WaterfallStep {
  final String label;
  final Money amount;
  final double start;
  final double end;
  final Color color;
  const WaterfallStep(this.label, this.amount, this.start, this.end, this.color);
}

/// From intäkter, down through each kostnadstyp, to the result. At most
/// [maxCosts] cost types are shown on their own; the rest are added up as
/// "Övriga kostnader".
List<WaterfallStep> waterfallSteps(ResultReport r, {int maxCosts = 5, Color? cost}) {
  final costColor = cost ?? AppTheme.pumpkin;
  final sales = r.sales.ore / 100;
  final costs = [...r.costs]..sort((a, b) => b.net.ore.compareTo(a.net.ore));
  final shown = costs.take(maxCosts).toList();
  final rest = Money.sum(costs.skip(maxCosts).map((c) => c.net));
  final steps = <WaterfallStep>[WaterfallStep('Intäkter', r.sales, 0, sales, AppTheme.seed)];
  var level = sales;
  void step(String label, Money net) {
    final next = level - net.ore / 100;
    steps.add(WaterfallStep(label, -net, next < level ? next : level, next < level ? level : next, costColor));
    level = next;
  }

  for (final c in shown) {
    step(c.label, c.net);
  }
  if (!rest.isZero) step('Övriga kostnader', rest);
  final result = r.result.ore / 100;
  steps.add(WaterfallStep('Resultat', r.result, result < 0 ? result : 0, result < 0 ? 0 : result,
      result < 0 ? AppTheme.warning : AppTheme.seed));
  return steps;
}

/// Horizontal waterfall: a label, then a bar floating where the step starts.
class ResultWaterfall extends StatelessWidget {
  final ResultReport report;
  const ResultWaterfall(this.report, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final steps = waterfallSteps(report);
    var lo = 0.0, hi = 0.0;
    for (final s in steps) {
      if (s.start < lo) lo = s.start;
      if (s.end > hi) hi = s.end;
    }
    final span = hi - lo;
    if (span <= 0) return const SizedBox.shrink();
    return Semantics(
      label: 'Från intäkter till resultat, steg för steg',
      child: Column(children: [
        for (final s in steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(
                width: 92,
                child: Text(s.label, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final left = (s.start - lo) / span * box.maxWidth;
                    final width = ((s.end - s.start) / span * box.maxWidth).clamp(3.0, box.maxWidth);
                    return SizedBox(
                      height: 16,
                      child: Stack(children: [
                        Positioned.fill(child: Align(alignment: Alignment.centerLeft, child: Container(height: 1, color: AppTheme.hairline))),
                        Positioned(
                          left: left.clamp(0.0, box.maxWidth - width),
                          width: width,
                          top: 0,
                          bottom: 0,
                          child: DecoratedBox(
                              decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(4))),
                        ),
                      ]),
                    );
                  },
                ),
              ),
              SizedBox(
                width: 84,
                child: Text(s.amount.format(compact: true),
                    textAlign: TextAlign.end, style: t.bodySmall?.merge(moneyStyle)),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Each kostnadstyp as a share of the sales (intäkter), largest first.
class CostShare extends StatelessWidget {
  final ResultReport report;
  const CostShare(this.report, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sales = report.sales.ore;
    if (sales <= 0 || report.costs.isEmpty) {
      return Text('Visas när det finns försäljning och kostnader under perioden.', style: t.bodySmall);
    }
    final costs = [...report.costs]..sort((a, b) => b.net.ore.compareTo(a.net.ore));
    return Column(children: [
      for (final c in costs.take(6))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(c.label, style: t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('${(c.net.ore * 100 / sales).toStringAsFixed(c.net.ore * 100 / sales < 10 ? 1 : 0).replaceAll('.', ',')} %',
                  style: t.titleSmall?.merge(moneyStyle)),
            ]),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (c.net.ore / sales).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: AppTheme.hairline,
                color: chartSecond,
              ),
            ),
          ]),
        ),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: Text('Andel av intäkterna exkl. moms.', style: t.bodySmall),
      ),
    ]);
  }
}
