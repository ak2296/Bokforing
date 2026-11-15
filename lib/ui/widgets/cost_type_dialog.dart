import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/settings_keys.dart';
import '../../domain/cost_types.dart';

/// "Ny kostnadstyp": the owner adds a type of their own for a cost that none of
/// the standard types fits. Returns the new type, saved, or null when cancelled.
Future<CostType?> addCostTypeDialog(BuildContext context) async {
  final controller = AppScope.read(context);
  final name = TextEditingController();
  final account = TextEditingController(text: '6990');
  final label = await showDialog<CostType>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Ny kostnadstyp'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Namn', hintText: 't.ex. Studentmedarbetare'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: account,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'BAS-konto (valfritt)',
            helperText: '6990 Övriga kostnader om du är osäker. Redovisaren kan ändra det.',
            helperMaxLines: 2,
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Avbryt')),
        FilledButton(
          onPressed: () {
            final n = name.text.trim();
            if (n.isEmpty) return;
            final a = int.tryParse(account.text.trim());
            Navigator.pop(context, CostType.newCustom(n, account: a != null && a >= 1000 && a <= 8999 ? a : 6990));
          },
          child: const Text('Lägg till'),
        ),
      ],
    ),
  );
  name.dispose();
  account.dispose();
  if (label == null) return null;
  CostType.custom = [...CostType.custom, label];
  await controller.repo.setSetting(SettingsKeys.customCostTypes, CostType.encodeCustom(CostType.custom));
  return label;
}

/// Removes one of the owner's own types. Invoices that use it keep the key and
/// show as "Ej vald kostnadstyp" until a type is chosen again.
Future<void> removeCostType(BuildContext context, CostType type) async {
  final controller = AppScope.read(context);
  CostType.custom = [for (final c in CostType.custom) if (c.key != type.key) c];
  await controller.repo.setSetting(SettingsKeys.customCostTypes, CostType.encodeCustom(CostType.custom));
}
