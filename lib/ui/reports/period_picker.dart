import 'package:flutter/material.dart';

import '../../domain/report_period.dart';
import '../app_icons.dart';

/// Month, quarter, half-year or year, and arrows to the one before and after.
class PeriodPicker extends StatelessWidget {
  final ReportPeriod value;
  final ValueChanged<ReportPeriod> onChanged;
  const PeriodPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: SegmentedButton<PeriodKind>(
          expandedInsets: EdgeInsets.zero,
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [for (final k in PeriodKind.values) ButtonSegment(value: k, label: Text(k.label))],
          selected: {value.kind},
          onSelectionChanged: (s) => onChanged(value.inKind(s.first)),
        ),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(tooltip: 'Föregående', icon: const Icon(AppIcons.chevronLeft), onPressed: () => onChanged(value.step(-1))),
        Flexible(child: Text(value.title, textAlign: TextAlign.center, style: t.titleMedium)),
        IconButton(tooltip: 'Nästa', icon: const Icon(AppIcons.chevronRight), onPressed: () => onChanged(value.step(1))),
      ]),
    ]);
  }
}
