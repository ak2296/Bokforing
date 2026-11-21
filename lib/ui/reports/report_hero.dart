import 'package:flutter/material.dart';

import '../app_icons.dart';
import '../theme.dart';
import '../widgets/ledger_parts.dart' show HeroStat;

/// The head of a report tab: the one figure that answers "how did it go",
/// with a few smaller figures under it. Green for the month, slate blue for
/// sales and the year, pumpkin for costs and the result.
class ReportHero extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  final List<(String, String)> chips;

  /// A second row of chips under [chips] (cash and card); a chip with a tap shows an arrow.
  final List<HeroStat> extraChips;
  const ReportHero(
      {super.key, required this.color, required this.label, required this.value, this.chips = const [], this.extraChips = const []});

  /// One row of equal chips: same width, same height, label on one line.
  Widget _row(TextTheme t, List<HeroStat> items) {
    const on = Colors.white;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, c) in items.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: on.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: c.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(c.label, maxLines: 1, style: t.labelSmall?.copyWith(color: on.withValues(alpha: 0.85))),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(c.value, maxLines: 1, style: t.titleSmall?.merge(moneyStyle).copyWith(color: on, fontWeight: FontWeight.w600)),
                        if (c.onTap != null) Icon(AppIcons.chevronRight, size: 16, color: on.withValues(alpha: 0.85)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }

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
          _row(t, [for (final c in chips) HeroStat(c.$1, c.$2)]),
        ],
        if (extraChips.isNotEmpty) ...[
          const SizedBox(height: 8),
          _row(t, extraChips),
        ],
      ]),
    );
  }
}
