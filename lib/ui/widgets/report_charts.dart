import 'dart:math' as math;

import 'package:flutter/material.dart';

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
