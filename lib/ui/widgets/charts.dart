import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

const chartSecond = Color(0xFFE8916E);
const chartPrevious = Color(0xFF9FB3AA);

/// Two bars per label, e.g. sales and expenses per month.
class PairedBarChart extends StatelessWidget {
  final List<String> labels;
  final List<double> first;
  final List<double> second;
  final String semanticLabel;
  const PairedBarChart(
      {super.key, required this.labels, required this.first, required this.second, required this.semanticLabel});

  @override
  Widget build(BuildContext context) => Semantics(
        label: semanticLabel,
        child: SizedBox(
          height: 140,
          width: double.infinity,
          child: CustomPaint(painter: _BarsPainter(labels, first, second)),
        ),
      );
}

class _BarsPainter extends CustomPainter {
  final List<String> labels;
  final List<double> first;
  final List<double> second;
  _BarsPainter(this.labels, this.first, this.second);

  @override
  void paint(Canvas canvas, Size size) {
    const labelSpace = 18.0;
    final chartH = size.height - labelSpace;
    final top = [...first, ...second].fold<double>(0, math.max);
    final slot = size.width / labels.length;
    final barW = math.min(14.0, slot / 3);
    void bar(double x, double v, Color c) {
      if (top <= 0 || v <= 0) return;
      final h = math.max(2.0, chartH * v / top);
      final r = RRect.fromRectAndCorners(Rect.fromLTWH(x, chartH - h, barW, h),
          topLeft: const Radius.circular(3), topRight: const Radius.circular(3));
      canvas.drawRRect(r, Paint()..color = c);
    }

    for (var i = 0; i < labels.length; i++) {
      final center = slot * i + slot / 2;
      bar(center - barW - 1, first[i], AppTheme.seed);
      bar(center + 1, second[i], chartSecond);
      final tp = TextPainter(
          text: TextSpan(text: labels[i], style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(center - tp.width / 2, chartH + 4));
    }
    canvas.drawLine(Offset(0, chartH), Offset(size.width, chartH), Paint()..color = AppTheme.hairline);
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => old.first != first || old.second != second;
}

/// Two lines over twelve months: this year solid, the year compared dashed.
class CompareLineChart extends StatelessWidget {
  final List<double> current;
  final List<double> previous;
  final String semanticLabel;
  const CompareLineChart({super.key, required this.current, required this.previous, required this.semanticLabel});

  @override
  Widget build(BuildContext context) => Semantics(
        label: semanticLabel,
        child: SizedBox(
          height: 160,
          width: double.infinity,
          child: CustomPaint(painter: _LinesPainter(current, previous)),
        ),
      );
}

class _LinesPainter extends CustomPainter {
  final List<double> current;
  final List<double> previous;
  _LinesPainter(this.current, this.previous);

  static const _ticks = {0: 'jan', 3: 'apr', 6: 'jul', 9: 'okt'};

  @override
  void paint(Canvas canvas, Size size) {
    const labelSpace = 18.0;
    final chartH = size.height - labelSpace;
    final values = [...current, ...previous];
    final hi = values.fold<double>(0, math.max);
    final lo = values.fold<double>(0, math.min);
    final span = hi - lo == 0 ? 1.0 : hi - lo;
    double x(int i) => 6 + (size.width - 12) * i / 11;
    double y(double v) => 6 + (chartH - 12) * (1 - (v - lo) / span);

    final grid = Paint()..color = AppTheme.hairline;
    for (final f in const [0.0, 0.5, 1.0]) {
      final gy = 6 + (chartH - 12) * f;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }

    final dashed = Paint()
      ..color = chartPrevious
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < previous.length - 1; i++) {
      final a = Offset(x(i), y(previous[i]));
      final b = Offset(x(i + 1), y(previous[i + 1]));
      final d = (b - a).distance;
      for (var t = 0.0; t < d; t += 7) {
        canvas.drawLine(a + (b - a) * (t / d), a + (b - a) * (math.min(t + 4, d) / d), dashed);
      }
    }

    final solid = Paint()
      ..color = AppTheme.seed
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final path = Path();
    for (var i = 0; i < current.length; i++) {
      i == 0 ? path.moveTo(x(i), y(current[i])) : path.lineTo(x(i), y(current[i]));
    }
    canvas.drawPath(path, solid);

    for (final e in _ticks.entries) {
      final tp = TextPainter(
          text: TextSpan(text: e.value, style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(math.max(0, x(e.key) - tp.width / 2), chartH + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _LinesPainter old) => old.current != current || old.previous != previous;
}

/// A small coloured square and a label, for chart legends.
class LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;
  const LegendDot(this.color, this.label, {super.key, this.dashed = false});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: dashed ? 12 : 9,
          height: dashed ? 2 : 9,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}
