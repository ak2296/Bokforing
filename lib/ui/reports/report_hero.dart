import 'package:flutter/material.dart';

import '../theme.dart';

/// The head of a report tab: the one figure that answers "how did it go",
/// with a few smaller figures under it. Green for the month, slate blue for
/// sales and the year, pumpkin for costs and the result.
class ReportHero extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  final List<(String, String)> chips;
  const ReportHero({super.key, required this.color, required this.label, required this.value, this.chips = const []});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const on = Colors.white;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.28)!],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.bodySmall?.copyWith(color: on.withValues(alpha: 0.88))),
        const SizedBox(height: 2),
        Text(value, style: t.headlineMedium?.merge(moneyStyle).copyWith(color: on, fontWeight: FontWeight.w600)),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(children: [
            for (final (i, c) in chips.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: on.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.$1, style: t.labelSmall?.copyWith(color: on.withValues(alpha: 0.85))),
                    Text(c.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall?.merge(moneyStyle).copyWith(color: on, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ],
          ]),
        ],
      ]),
    );
  }
}
