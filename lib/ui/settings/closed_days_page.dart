import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../domain/closed_days.dart';
import '../../domain/dates.dart';
import '../app_icons.dart';
import '../widgets/common.dart';
import '../widgets/ledger_parts.dart';

/// "Stängda dagar": the weekdays the shop is always closed and single days it
/// was closed (a holiday, an unplanned closing). No Z-report is expected on
/// those days: they are left out of "5 av 6" and never shown as missing.
class ClosedDaysPage extends StatefulWidget {
  const ClosedDaysPage({super.key});

  @override
  State<ClosedDaysPage> createState() => _ClosedDaysPageState();
}

class _ClosedDaysPageState extends State<ClosedDaysPage> {
  ClosedDays? _closed;
  static const _names = ['Mån', 'Tis', 'Ons', 'Tor', 'Fre', 'Lör', 'Sön'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_closed == null) {
      AppScope.read(context).repo.closedDays().then((c) {
        if (mounted) setState(() => _closed = c);
      });
    }
  }

  Future<void> _save(ClosedDays c) async {
    final controller = AppScope.read(context);
    setState(() => _closed = c);
    await controller.repo.saveClosedDays(c);
    controller.dataChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = _closed;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Stängda dagar')),
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text(
                  'På en stängd dag väntar appen ingen Z-rapport. Dagen räknas inte i "5 av 6" och visas aldrig som saknad. '
                  'Har du ändå en Z-rapport för dagen räknas den med.',
                  style: t.bodySmall),
              const SectionTitle('Veckodagar som alltid är stängda'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(_names[d - 1]),
                    selected: c.weekdays.contains(d),
                    onSelected: (on) => _save(c.withWeekdays(on ? {...c.weekdays, d} : ({...c.weekdays}..remove(d)))),
                  ),
              ]),
              const SectionTitle('Enstaka stängda dagar'),
              if (c.dates.isEmpty)
                const EmptyState(icon: AppIcons.calendar, text: 'Inga enstaka stängda dagar.')
              else
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final d in (c.dates.toList()..sort()).reversed)
                    InputChip(label: Text(SwedishDates.mediumDay(d)), onDeleted: () => _save(c.withoutDate(d))),
                ]),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(AppIcons.add),
                label: const Text('Lägg till en stängd dag'),
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: now,
                    firstDate: DateTime(now.year - 2),
                    lastDate: DateTime(now.year + 1, 12, 31),
                  );
                  if (picked != null) await _save(c.withDate(SwedishDates.iso(picked)));
                },
              ),
              const SizedBox(height: 8),
              Text('Du kan också säga att en dag var stängd direkt på Försäljning, när en Z-rapport saknas.', style: t.bodySmall),
            ]),
    );
  }
}
