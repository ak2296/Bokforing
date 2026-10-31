import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../domain/models.dart';

/// "Fält på Z-rapport": what each printed line on the Z-report is recorded
/// as. Different cash registers and shops print different lines, so the
/// owner decides. Lines pointing to the same category are added together.
class ZFieldsPage extends StatefulWidget {
  const ZFieldsPage({super.key});

  @override
  State<ZFieldsPage> createState() => _ZFieldsPageState();
}

class _ZFieldsPageState extends State<ZFieldsPage> {
  List<Category>? _cats;
  List<({String label, int? categoryId})> _rules = const [];

  static const _notCounted = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cats == null) _load();
  }

  Future<void> _load() async {
    final repo = AppScope.read(context).repo;
    final cats = await repo.categories();
    final rules = await repo.zLabelRules();
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _rules = rules;
    });
  }

  Future<void> _set(String label, int? categoryId) async {
    await AppScope.read(context).repo.setZLabelRule(label, categoryId);
    await _load();
  }

  Future<void> _edit({String label = '', int? categoryId}) async {
    final cats = _cats!;
    final text = TextEditingController(text: label);
    var selected = categoryId ?? (label.isEmpty && cats.isNotEmpty ? cats.first.id! : _notCounted);
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text(label.isEmpty ? 'Ny rad från Z-rapporten' : 'Ändra rad'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: text,
                autofocus: label.isEmpty,
                enabled: label.isEmpty,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Text på Z-rapporten',
                  hintText: 't.ex. Drycka avhämtning',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Registreras som'),
                items: [
                  for (final cat in cats) DropdownMenuItem(value: cat.id, child: Text('${cat.name} (${cat.vat.label})')),
                  const DropdownMenuItem(value: _notCounted, child: Text('Räknas inte med')),
                ],
                onChanged: (v) => setState(() => selected = v ?? _notCounted),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Avbryt')),
            FilledButton(
              onPressed: () {
                if (text.text.trim().isEmpty) return;
                Navigator.pop(c, (text.text.trim(), selected));
              },
              child: const Text('Spara'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _set(result.$1, result.$2 == _notCounted ? null : result.$2);
  }

  @override
  Widget build(BuildContext context) {
    final cats = _cats;
    final t = Theme.of(context).textTheme;
    String name(int? id) =>
        id == null ? 'Räknas inte med' : (cats?.where((c) => c.id == id).firstOrNull?.name ?? 'Borttagen kategori');
    return Scaffold(
      appBar: AppBar(title: const Text('Fält på Z-rapport')),
      floatingActionButton: cats == null || cats.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Lägg till rad'),
            ),
      body: cats == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                const Text(
                  'Bestäm vad varje rad på din Z-rapport ska registreras som. Flera rader kan räknas till samma '
                  'kategori, t.ex. "Mat avhämtning" och "Drycka avhämtning" till "Avhämtning". De läggs då ihop till '
                  'ett belopp i månads- och årsrapporten.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Rader med exakt samma namn som en kategori kopplas automatiskt. Kategorier och momssatser ändrar du '
                  'under Försäljningskategorier.',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 16),
                if (cats.isEmpty)
                  const Text('Lägg först till försäljningskategorier under Inställningar → Försäljningskategorier.')
                else if (_rules.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('Inga egna rader ännu.'),
                      subtitle: Text('Tryck på "Lägg till rad". Raderna sparas också när du väljer "Kom ihåg" vid granskning.'),
                    ),
                  ),
                for (final r in _rules)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text('"${r.label}"'),
                      subtitle: Text('Registreras som: ${name(r.categoryId)}'),
                      onTap: () => _edit(label: r.label, categoryId: r.categoryId),
                      trailing: IconButton(
                        tooltip: 'Ta bort raden',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await AppScope.read(context).repo.deleteZLabelRule(r.label);
                          await _load();
                        },
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
