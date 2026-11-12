import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/dates.dart';
import '../../domain/money.dart';
import '../theme.dart';

/// One bar per label from a zero line: up in green for a profit, down in
/// orange-brown for a loss (e.g. the result of each month).
class SignedBarChart extends StatelessWidget {
  final List<String> labels;
  final List<double> values;
  final String semanticLabel;
  const SignedBarChart({super.key, required this.labels, required this.values, required this.semanticLabel});

  @override
  Widget build(BuildContext context) => Semantics(
        label: semanticLabel,
        child: SizedBox(
          height: 150,
          width: double.infinity,
          child: CustomPaint(painter: _SignedPainter(labels, values)),
        ),
      );
}

class _SignedPainter extends CustomPainter {
  final List<String> labels;
  final List<double> values;
  final bool _dark = AppTheme.dark;
  _SignedPainter(this.labels, this.values);

  @override
  void paint(Canvas canvas, Size size) {
    const labelSpace = 18.0;
    final chartH = size.height - labelSpace;
    final hi = values.fold<double>(0, math.max);
    final lo = values.fold<double>(0, math.min);
    final span = hi - lo;
    final slot = size.width / labels.length;
    final barW = math.min(16.0, slot * 0.6);
    final zeroY = span <= 0 ? chartH : chartH * hi / span;
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), Paint()..color = AppTheme.hairline);
    for (var i = 0; i < labels.length; i++) {
      final center = slot * i + slot / 2;
      final v = values[i];
      if (span > 0 && v != 0) {
        final h = math.max(2.0, chartH * v.abs() / span);
        final rect = v > 0 ? Rect.fromLTWH(center - barW / 2, zeroY - h, barW, h) : Rect.fromLTWH(center - barW / 2, zeroY, barW, h);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)),
            Paint()..color = v > 0 ? AppTheme.seed : AppTheme.pumpkin);
      }
      final tp = TextPainter(
          text: TextSpan(text: labels[i], style: TextStyle(fontSize: 10, color: AppTheme.muted)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(center - tp.width / 2, chartH + 4));
    }
  }

  @override
  bool shouldRepaint(_SignedPainter old) => old.values != values || old.labels != labels || old._dark != _dark;
}

/// A month as a calendar, weeks in rows, Monday first. The more was sold on a
/// day, the stronger the green. Days without sales are grey.
class SalesHeatMap extends StatelessWidget {
  final int year;
  final int month;

  /// Sales per day of the month.
  final Map<int, Money> byDay;
  const SalesHeatMap({super.key, required this.year, required this.month, required this.byDay});

  static const _weekdays = ['mån', 'tis', 'ons', 'tor', 'fre', 'lör', 'sön'];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final days = DateTime(year, month + 1, 0).day;
    final lead = DateTime(year, month, 1).weekday - 1;
    final top = byDay.values.fold<int>(0, (m, v) => math.max(m, v.ore));
    final cells = <int?>[for (var i = 0; i < lead; i++) null, for (var d = 1; d <= days; d++) d];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    Widget cell(int? d) {
      if (d == null) return const Expanded(child: SizedBox(height: 38));
      final v = byDay[d];
      final frac = v == null || top <= 0 ? 0.0 : (v.ore / top).clamp(0.0, 1.0);
      final has = v != null && v.ore > 0;
      final fill = has ? AppTheme.seed.withValues(alpha: 0.18 + 0.82 * frac) : AppTheme.hairline;
      final text = has && frac > 0.55 ? Colors.white : AppTheme.ink;
      return Expanded(
        child: Semantics(
          excludeSemantics: true,
          label: '$d ${SwedishDates.shortMonths[month - 1]}: ${has ? v.format() : 'ingen försäljning'}',
          child: Container(
            height: 38,
            margin: const EdgeInsets.all(2),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(8)),
            child: Text('$d', style: t.bodySmall?.copyWith(color: has ? text : AppTheme.muted)),
          ),
        ),
      );
    }

    return Column(children: [
      Row(children: [
        for (final w in _weekdays)
          Expanded(child: Center(child: Text(w, style: t.bodySmall?.copyWith(fontSize: 10.5)))),
      ]),
      const SizedBox(height: 2),
      for (var w = 0; w < cells.length ~/ 7; w++) Row(children: [for (var i = 0; i < 7; i++) cell(cells[w * 7 + i])]),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Text('Mindre', style: t.bodySmall),
        const SizedBox(width: 6),
        for (final a in const [0.18, 0.4, 0.65, 1.0])
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(color: AppTheme.seed.withValues(alpha: a), borderRadius: BorderRadius.circular(4)),
          ),
        const SizedBox(width: 6),
        Text('Mer', style: t.bodySmall),
      ]),
    ]);
  }
}
