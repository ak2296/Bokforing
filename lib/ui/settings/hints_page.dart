import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../app_icons.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// "Inlärda fält": where each supplier prints a field, learned from the
/// user's corrections. Each can be removed; the app then reads that field
/// with the normal rules again.
class HintsPage extends StatelessWidget {
  const HintsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Inlärda fält')),
        body: Reloading(
          loader: (c) => c.repo.allHints(),
          builder: (context, hints) {
            final t = Theme.of(context).textTheme;
            if (hints.isEmpty) {
              return const EmptyState(
                icon: AppIcons.rules,
                text: 'Inget inlärt ännu. När du rättar ett fält efter en skanning, och rätt värde står på pappret, '
                    'lär sig appen var just den leverantören skriver det.',
              );
            }
            String? last;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Appen läser fältet efter de här orden på leverantörens papper först. Ett värde som hittas så '
                    'markeras "Kontrollera".', style: t.bodySmall),
                const SizedBox(height: 8),
                for (final h in hints) ...[
                  if (h.supplier != last) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                      child: Text(last = h.supplier, style: t.titleSmall),
                    ),
                  ],
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      title: Text(h.field.label),
                      subtitle: Text('Efter "${h.label}"${h.hits > 1 ? ' · stämt ${h.hits} gånger' : ''}'),
                      trailing: IconButton(
                        tooltip: 'Glöm',
                        icon: const Icon(AppIcons.delete, color: AppTheme.muted),
                        onPressed: () async {
                          final c = AppScope.read(context);
                          await c.repo.forgetHint(h.key, h.field);
                          c.dataChanged();
                        },
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      );
}
