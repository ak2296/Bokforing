import 'package:flutter/material.dart';

import '../../domain/cost_types.dart';
import '../app_icons.dart';
import '../widgets/common.dart';
import '../widgets/ledger_parts.dart';
import '../widgets/cost_type_dialog.dart';

/// "Egna kostnadstyper": types the owner added for costs that no standard type
/// covers, and the standard ones for reference.
class CostTypesPage extends StatefulWidget {
  const CostTypesPage({super.key});

  @override
  State<CostTypesPage> createState() => _CostTypesPageState();
}

class _CostTypesPageState extends State<CostTypesPage> {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Kostnadstyper')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(
            'Kostnadstyperna delar upp utgifterna i resultatrapporten och SIE-filen. Saknas en som passar, lägg till en egen. '
            'Du kan också göra det när du kontrollerar en faktura.',
            style: t.bodySmall),
        const SizedBox(height: 12),
        const SectionTitle('Dina egna'),
        if (CostType.custom.isEmpty)
          const EmptyState(icon: AppIcons.rules, text: 'Du har inte lagt till några egna kostnadstyper.')
        else
          for (final c in CostType.custom)
            Card(
              child: ListTile(
                title: Text(c.label),
                subtitle: Text('BAS-konto ${c.account}'),
                trailing: IconButton(
                  icon: const Icon(AppIcons.delete),
                  tooltip: 'Ta bort',
                  onPressed: () async {
                    final ok = await confirmDialog(context,
                        title: 'Ta bort kostnadstypen?',
                        message: 'Fakturor som använder den visas som "Ej vald kostnadstyp" tills du väljer en ny.',
                        confirm: 'Ta bort');
                    if (!ok || !context.mounted) return;
                    await removeCostType(context, c);
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(AppIcons.add),
          label: const Text('Ny kostnadstyp'),
          onPressed: () async {
            await addCostTypeDialog(context);
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(height: 16),
        const SectionTitle('Standardtyper'),
        for (final c in CostType.all)
          ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(c.label), trailing: Text('${c.account}', style: t.bodySmall)),
      ]),
    );
  }
}
