import 'package:flutter/material.dart';

import '../app_icons.dart';

import '../../domain/models.dart';
import '../../domain/vat.dart';

/// Editable category while the user sets up the list. [vat] stays null until
/// the user picks a rate: the app never assigns one from the name.
class CategoryDraft {
  final int? id;
  String name;
  VatRate? vat;
  CategoryDraft({this.id, required this.name, this.vat});

  factory CategoryDraft.from(Category c) => CategoryDraft(id: c.id, name: c.name, vat: c.vat);

  Category toCategory(int order) => Category(id: id, name: name.trim(), vat: vat!, sortOrder: order);
}

/// Add / rename / delete / reorder categories and pick a VAT rate for each.
class CategoryListEditor extends StatelessWidget {
  final List<CategoryDraft> drafts;
  final List<VatRate> rates;
  final bool showVat;
  final bool showNames;
  final VoidCallback onChanged;
  final ValueChanged<VatRate> onAddRate;

  const CategoryListEditor({
    super.key,
    required this.drafts,
    required this.rates,
    required this.onChanged,
    required this.onAddRate,
    this.showVat = true,
    this.showNames = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (drafts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Inga kategorier ännu. Tryck på "Lägg till kategori".'),
          ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: drafts.length,
          onReorderItem: (from, to) {
            final d = drafts.removeAt(from);
            drafts.insert(to, d);
            onChanged();
          },
          itemBuilder: (context, i) {
            final d = drafts[i];
            return Card(
              key: ObjectKey(d),
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(AppIcons.drag, semanticLabel: 'Ändra ordning'),
                      ),
                    ),
                    Expanded(
                      child: Text(d.name,
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (showVat) _RatePicker(draft: d, rates: rates, onChanged: onChanged, onAddRate: onAddRate),
                    if (showNames) ...[
                      IconButton(
                        tooltip: 'Redigera kategori',
                        icon: const Icon(AppIcons.edit),
                        onPressed: () async {
                          final name = await askCategoryName(context, initial: d.name);
                          if (name != null) {
                            d.name = name;
                            onChanged();
                          }
                        },
                      ),
                      IconButton(
                        tooltip: 'Ta bort kategori',
                        icon: const Icon(AppIcons.delete),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Ta bort kategori?'),
                              content: Text(
                                  '"${d.name}" tas bort från listan. Redan sparade dagar behåller sina belopp.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Avbryt')),
                                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ta bort')),
                              ],
                            ),
                          );
                          if (ok == true) {
                            drafts.remove(d);
                            onChanged();
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        if (showNames)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              icon: const Icon(AppIcons.add),
              label: const Text('Lägg till kategori'),
              onPressed: () async {
                final name = await askCategoryName(context);
                if (name != null) {
                  drafts.add(CategoryDraft(name: name));
                  onChanged();
                }
              },
            ),
          ),
      ],
    );
  }
}

class _RatePicker extends StatelessWidget {
  final CategoryDraft draft;
  final List<VatRate> rates;
  final VoidCallback onChanged;
  final ValueChanged<VatRate> onAddRate;
  const _RatePicker({required this.draft, required this.rates, required this.onChanged, required this.onAddRate});

  static const _other = -1;

  @override
  Widget build(BuildContext context) {
    final all = {...rates, ?draft.vat}.toList()..sort();
    return DropdownButton<int>(
      value: draft.vat?.basisPoints,
      hint: Text('Välj moms', style: TextStyle(color: Theme.of(context).colorScheme.error)),
      underline: const SizedBox.shrink(),
      items: [
        for (final r in all) DropdownMenuItem(value: r.basisPoints, child: Text(r.label)),
        const DropdownMenuItem(value: _other, child: Text('Annan…')),
      ],
      onChanged: (v) async {
        if (v == null) return;
        if (v == _other) {
          final rate = await _askRate(context);
          if (rate == null) return;
          onAddRate(rate);
          draft.vat = rate;
        } else {
          draft.vat = VatRate(v);
        }
        onChanged();
      },
    );
  }

  Future<VatRate?> _askRate(BuildContext context) async {
    final ctrl = TextEditingController();
    String? error;
    return showDialog<VatRate>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('Annan momssats'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Momssats i procent', suffixText: '%', errorText: error),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Avbryt')),
            FilledButton(
              onPressed: () {
                final r = VatRate.parse(ctrl.text);
                if (r == null) {
                  setState(() => error = 'Ange t.ex. 6, 12 eller 25');
                } else {
                  Navigator.pop(c, r);
                }
              },
              child: const Text('Lägg till'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> askCategoryName(BuildContext context, {String initial = ''}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(initial.isEmpty ? 'Lägg till kategori' : 'Redigera kategori'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Namn'),
        onSubmitted: (v) => Navigator.pop(c, v.trim().isEmpty ? null : v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Avbryt')),
        FilledButton(
          onPressed: () => Navigator.pop(c, ctrl.text.trim().isEmpty ? null : ctrl.text.trim()),
          child: const Text('Spara'),
        ),
      ],
    ),
  );
}

/// VAT hints for the current date. Shown only as help; never applied.
class VatGuidanceCard extends StatelessWidget {
  const VatGuidanceCard({super.key});

  @override
  Widget build(BuildContext context) {
    final rules = VatRuleSet.current;
    final hints = rules.guidanceOn(DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vägledning om momssatser', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final h in hints) Text('• ${h.text}'),
            const SizedBox(height: 6),
            Text(
              'Appen väljer aldrig momssats åt dig. Kontrollera på skatteverket.se om du är osäker. '
              'Källa: ${rules.source}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
