import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/settings_keys.dart';
import '../domain/category_templates.dart';
import '../domain/models.dart';
import '../domain/vat.dart';
import 'settings/category_editor.dart';

/// First-run setup: company name, sales categories and a VAT rate per
/// category. Nothing is stored until the last step.
class SetupWizard extends StatefulWidget {
  final VoidCallback onDone;
  const SetupWizard({super.key, required this.onDone});

  @override
  State<SetupWizard> createState() => _SetupWizardState();
}

class _SetupWizardState extends State<SetupWizard> {
  int _step = 0;
  final _name = TextEditingController();
  final List<CategoryDraft> _drafts = [];
  List<VatRate> _rates = VatRuleSet.current.rates;
  final List<VatRate> _addedRates = [];
  CategoryTemplate? _template;
  bool _saving = false;

  static const _stepCount = 5;

  bool get _canContinue => switch (_step) {
        1 => _name.text.trim().isNotEmpty,
        2 => _template != null,
        3 => _drafts.every((d) => d.vat != null),
        _ => true,
      };

  String? get _blockedReason => switch (_step) {
        1 => 'Skriv företagets namn för att fortsätta.',
        2 => 'Välj en utgångspunkt för kategorierna.',
        3 => 'Välj momssats för alla kategorier.',
        _ => null,
      };

  void _pickTemplate(CategoryTemplate t) {
    setState(() {
      _template = t;
      _drafts
        ..clear()
        ..addAll(t.names.map((n) => CategoryDraft(name: n)));
    });
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final repo = AppScope.read(context).repo;
    for (final r in _addedRates) {
      await repo.addVatRate(r);
    }
    await repo.saveProfile(BusinessProfile(name: _name.text));
    await repo.saveCategories([for (var i = 0; i < _drafts.length; i++) _drafts[i].toCategory(i)]);
    await repo.setBoolSetting(SettingsKeys.setupDone, true);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final body = switch (_step) {
      0 => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Välkommen', style: t.headlineMedium),
            const SizedBox(height: 12),
            Text('Vi hjälper dig att registrera fakturor och dagsförsäljning.', style: t.titleMedium),
            const SizedBox(height: 16),
            const Text(
                'Allt sparas bara i telefonen. Inget registreras utan att du först har kontrollerat och godkänt uppgifterna.'),
          ],
        ),
      1 => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Företagsnamn', style: t.headlineSmall),
            const SizedBox(height: 12),
            const Text('Namnet visas överst i månadsrapporten och i PDF-filen.'),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Företagsnamn'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      2 => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Försäljningskategorier', style: t.headlineSmall),
            const SizedBox(height: 8),
            const Text('Vilka försäljningskategorier vill du registrera från Z-rapporten?'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tpl in CategoryTemplate.all)
                  ChoiceChip(
                    label: Text(tpl.title),
                    selected: _template == tpl,
                    onSelected: (_) => _pickTemplate(tpl),
                  ),
              ],
            ),
            if (_template != null) ...[
              const SizedBox(height: 12),
              const Text('Lägg till, byt namn, ta bort eller dra för att ändra ordning.'),
              CategoryListEditor(
                drafts: _drafts,
                rates: _rates,
                showVat: false,
                onChanged: () => setState(() {}),
                onAddRate: (_) {},
              ),
            ],
          ],
        ),
      3 => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Momssats per kategori', style: t.headlineSmall),
            const SizedBox(height: 8),
            const Text('Välj momssats för varje kategori. Samma vara kan ha olika moms beroende på hur den säljs.'),
            const SizedBox(height: 12),
            const VatGuidanceCard(),
            const SizedBox(height: 8),
            if (_drafts.isEmpty) const Text('Du har inga kategorier. Du kan lägga till dem senare i Inställningar.'),
            CategoryListEditor(
              drafts: _drafts,
              rates: _rates,
              showNames: false,
              onChanged: () => setState(() {}),
              onAddRate: (r) => setState(() {
                _addedRates.add(r);
                _rates = {..._rates, r}.toList()..sort();
              }),
            ),
          ],
        ),
      _ => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Inställningen är klar.', style: t.headlineSmall),
            const SizedBox(height: 12),
            Text('Företag: ${_name.text.trim()}'),
            const SizedBox(height: 8),
            for (final d in _drafts) Text('${d.name}: ${d.vat?.label ?? '-'}'),
            const SizedBox(height: 12),
            const Text('Du kan ändra allt senare under Inställningar.'),
          ],
        ),
    };

    final last = _step == _stepCount - 1;
    return Scaffold(
      appBar: AppBar(
        title: Text('Kom igång (${_step + 1} av $_stepCount)'),
        leading: _step > 0
            ? IconButton(
                tooltip: 'Tillbaka',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _step--))
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(value: (_step + 1) / _stepCount),
            Expanded(
              child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: body),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_canContinue && _blockedReason != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_blockedReason!, textAlign: TextAlign.center),
                    ),
                  FilledButton(
                    onPressed: !_canContinue || _saving
                        ? null
                        : last
                            ? _finish
                            : () => setState(() => _step++),
                    child: Text(last ? 'Börja använda appen' : 'Fortsätt'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
