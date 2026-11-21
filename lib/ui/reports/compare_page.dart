import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../domain/money.dart';
import '../../domain/reports.dart';
import '../../domain/dates.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// What "Jämför år" compares.
enum _Metric {
  sales('Försäljning'),
  expenses('Utgifter'),
  result('Resultat (exkl. moms)'),
  vat('Moms att betala');

  final String label;
  const _Metric(this.label);

  Money of(YearRow r) => switch (this) {
        _Metric.sales => r.sales,
        _Metric.expenses => r.expenses,
        _Metric.result => (r.sales - r.outputVat) - (r.expenses - r.inputVat),
        _Metric.vat => r.vatDifference,
      };
}

/// "Jämför år": two to four years side by side, month by month or quarter by quarter,
/// for sales, expenses, result or moms. Opens from the button on the start page.
class ComparePage extends StatefulWidget {
  const ComparePage({super.key});

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  static final _now = DateTime.now();
  final Set<int> _years = {_now.year, _now.year - 1};
  _Metric _metric = _Metric.sales;
  bool _quarters = false;

  /// One colour per year, the newest first.
  static const _colors = [Color(0xFF7C5CFF), Color(0xFF3A5A8C), Color(0xFF0B6B4E), Color(0xFFE2600D)];

  static Future<YearReport> _load(AppController c, int y) async => const ReportGenerator().yearly(
        year: y,
        sales: await c.repo.dailySalesBetween('$y-01-01', '$y-12-31'),
        invoices: await c.repo.invoicesForReports('$y-01-01', '$y-12-31'),
        online: await c.repo.onlineSalesBetween('$y-01-01', '$y-12-31'),
      );

  List<int> get _sorted => _years.toList()..sort((a, b) => b.compareTo(a));

  Color _color(int year) => _colors[_sorted.indexOf(year).clamp(0, 3)];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final years = _sorted;
    return Scaffold(
      appBar: AppBar(title: const Text('Jämför år')),
      body: Reloading<List<YearReport>>(
        deps: years.join(','),
        loader: (c) async => [for (final y in years) await _load(c, y)],
        builder: (context, reports) {
          // Months or quarters as rows: each cell is the metric summed over the period.
          final slots = _quarters ? 4 : 12;
          final per = 12 ~/ slots;
          String label(int i) => _quarters ? 'Kv ${i + 1}' : SwedishDates.capitalize(SwedishDates.shortMonths[i]);
          Money cell(YearReport r, int i) => Money.sum([for (var m = i * per; m < (i + 1) * per; m++) _metric.of(r.rows[m])]);
          final nowYear = _now.year;
          // The running year only counts the months that have passed, so totals compare fairly.
          int monthsOf(YearReport r) => r.year == nowYear ? _now.month : 12;
          Money total(YearReport r) => Money.sum([for (var m = 0; m < monthsOf(r); m++) _metric.of(r.rows[m])]);
          final values = [
            for (final r in reports) [for (var i = 0; i < slots; i++) cell(r, i)],
          ];
          final maxAbs = values.expand((v) => v).fold<int>(1, (a, m) => m.ore.abs() > a ? m.ore.abs() : a);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text('ÅR (VÄLJ 2–4)', style: t.labelMedium?.copyWith(color: AppTheme.muted, letterSpacing: 0.4)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var y = nowYear; y >= nowYear - 5; y--)
                  FilterChip(
                    label: Text('$y'),
                    selected: _years.contains(y),
                    selectedColor: _years.contains(y) ? _color(y) : null,
                    labelStyle: TextStyle(color: _years.contains(y) ? Colors.white : null, fontWeight: FontWeight.w600),
                    checkmarkColor: Colors.white,
                    onSelected: (v) => setState(() {
                      if (v && _years.length < 4) _years.add(y);
                      if (!v && _years.length > 2) _years.remove(y);
                    }),
                  ),
              ]),
              const SizedBox(height: 14),
              Text('SIFFRA', style: t.labelMedium?.copyWith(color: AppTheme.muted, letterSpacing: 0.4)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in _Metric.values)
                  ChoiceChip(label: Text(m.label), selected: _metric == m, onSelected: (_) => setState(() => _metric = m)),
              ]),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [ButtonSegment(value: false, label: Text('Månad')), ButtonSegment(value: true, label: Text('Kvartal'))],
                selected: {_quarters},
                onSelectionChanged: (s) => setState(() => _quarters = s.first),
              ),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    height: 170,
                    child: Semantics(
                      label: '${_metric.label} per ${_quarters ? 'kvartal' : 'månad'}, ${years.join(', ')}',
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _LinesPainter(values: values, colors: [for (final r in reports) _color(r.year)], maxAbs: maxAbs, grid: AppTheme.hairline, labelColor: AppTheme.muted, labels: [for (var i = 0; i < slots; i++) label(i)]),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: Text(_metric.label, style: t.labelMedium?.copyWith(color: AppTheme.muted))),
                      for (final r in reports)
                        SizedBox(
                          width: 78,
                          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: _color(r.year), shape: BoxShape.circle)),
                            const SizedBox(width: 4),
                            Text('${r.year}', style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                          ]),
                        ),
                    ]),
                    for (var i = 0; i < slots; i++) ...[
                      Divider(height: 14, color: AppTheme.hairline),
                      Row(children: [
                        Expanded(child: Text(label(i))),
                        for (final (j, r) in reports.indexed)
                          SizedBox(
                            width: 78,
                            child: Text(i * per < monthsOf(r) ? values[j][i].format(unit: false, compact: true) : '–',
                                textAlign: TextAlign.end, style: t.bodyMedium?.merge(moneyStyle)),
                          ),
                      ]),
                    ],
                    Divider(height: 18, color: AppTheme.fieldBorder),
                    Row(children: [
                      Expanded(child: Text(reports.any((r) => r.year == nowYear) ? 'Hittills' : 'Totalt', style: t.titleSmall)),
                      for (final r in reports)
                        SizedBox(
                          width: 78,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(total(r).format(unit: false, compact: true), style: t.titleSmall?.merge(moneyStyle)),
                          ),
                        ),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              ..._insight(context, reports, total, monthsOf),
            ],
          );
        },
      ),
    );
  }

  /// A sentence about the newest year against the one before, over the same months.
  List<Widget> _insight(BuildContext context, List<YearReport> reports, Money Function(YearReport) total, int Function(YearReport) monthsOf) {
    if (reports.length < 2) return const [];
    final a = reports[0], b = reports[1];
    final months = monthsOf(a) < monthsOf(b) ? monthsOf(a) : monthsOf(b);
    Money upTo(YearReport r) => Money.sum([for (var m = 0; m < months; m++) _metric.of(r.rows[m])]);
    final x = upTo(a), y = upTo(b);
    if (y.isZero) return const [];
    final change = (x.ore - y.ore) * 100 / y.ore.abs();
    final sign = change >= 0 ? '+' : '−';
    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppTheme.tint, borderRadius: BorderRadius.circular(14)),
        child: Text('${_metric.label} $months första månaderna: ${a.year} mot ${b.year} $sign${change.abs().toStringAsFixed(0)} %.',
            style: Theme.of(context).textTheme.bodyMedium),
      ),
    ];
  }
}

/// One line per year over the slots; zero in the middle when a value is negative.
class _LinesPainter extends CustomPainter {
  final List<List<Money>> values;
  final List<Color> colors;
  final int maxAbs;
  final Color grid;
  final Color labelColor;
  final List<String> labels;
  _LinesPainter({required this.values, required this.colors, required this.maxAbs, required this.grid, required this.labelColor, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    final hasNegative = values.any((v) => v.any((m) => m.isNegative));
    const bottom = 16.0;
    final h = size.height - bottom;
    double y(Money m) => hasNegative ? h / 2 - m.ore / maxAbs * (h / 2 - 4) : h - 4 - m.ore / maxAbs * (h - 8);
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      canvas.drawLine(Offset(0, f * h), Offset(size.width, f * h), gridPaint);
    }
    final n = labels.length;
    double x(int i) => n == 1 ? size.width / 2 : i * size.width / (n - 1);
    for (final (j, v) in values.indexed) {
      final p = Paint()
        ..color = colors[j]
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      for (var i = 0; i < v.length; i++) {
        i == 0 ? path.moveTo(x(i), y(v[i])) : path.lineTo(x(i), y(v[i]));
      }
      canvas.drawPath(path, p);
    }
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final i in {0, n ~/ 3, 2 * n ~/ 3, n - 1}) {
      tp.text = TextSpan(text: labels[i], style: TextStyle(fontSize: 10, color: labelColor));
      tp.layout();
      tp.paint(canvas, Offset((x(i) - tp.width / 2).clamp(0, size.width - tp.width), size.height - 13));
    }
  }

  @override
  bool shouldRepaint(_LinesPainter old) => old.values != values || old.colors != colors;
}
