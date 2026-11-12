import 'package:flutter/material.dart';

import 'app_icons.dart';

import '../app/app_controller.dart';
import '../app/settings_keys.dart';
import '../domain/category_templates.dart';
import '../domain/models.dart';
import '../domain/vat.dart';
import 'settings/backup_page.dart';
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
  final _org = TextEditingController();
  final _address = TextEditingController();
  CompanyForm? _form;
  final List<CategoryDraft> _drafts = [];
  List<VatRate> _rates = VatRuleSet.current.rates;
  final List<VatRate> _addedRates = [];
  CategoryTemplate? _template;
  bool _saving = false;
  final List<_ZRuleDraft> _zRules = [];

  static const _stepCount = 6;

  bool get _canContinue => switch (_step) {
        1 => _name.text.trim().isNotEmpty && _form != null,
        2 => _template != null,
        3 => _drafts.every((d) => d.vat != null),
        _ => true,
      };

  String? get _blockedReason => switch (_step) {
        1 => 'Skriv företagets namn och välj företagsform för att fortsätta.',
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

  /// Restores a backup instead of the steps; the settings come with it.
  Future<void> _restore() async {
    final repo = AppScope.read(context).repo;
    if (!await restoreBackupFromFile(context)) return;
    await repo.setBoolSetting(SettingsKeys.setupDone, true);
    widget.onDone();
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    final repo = AppScope.read(context).repo;
    for (final r in _addedRates) {
      await repo.addVatRate(r);
    }
    await repo.saveProfile(BusinessProfile(name: _name.text, orgNumber: _org.text, address: _address.text));
    await repo.setCompanyForm(_form!);
    await repo.saveCategories([for (var i = 0; i < _drafts.length; i++) _drafts[i].toCategory(i)]);
    // Categories now have ids; they are saved in the same order as drafts.
    final saved = await repo.categories();
    for (final r in _zRules) {
      if (r.label.text.trim().isEmpty) continue;
      final idx = r.target == null ? -1 : _drafts.indexOf(r.target!);
      await repo.setZLabelRule(r.label.text, idx < 0 || idx >= saved.length ? null : saved[idx].id);
    }
    await repo.setBoolSetting(SettingsKeys.setupDone, true);
    widget.onDone();
  }

  Widget _zRuleRow(_ZRuleDraft r) => Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: r.label,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Text på Z-rapporten', isDense: true),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ta bort raden',
                    icon: const Icon(AppIcons.close),
                    onPressed: () => setState(() => _zRules.remove(r)),
                  ),
                ],
              ),
              Row(
                children: [
                  const Text('Registreras som: '),
                  Expanded(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: r.target == null ? -1 : _drafts.indexOf(r.target!),
                      items: [
                        for (var i = 0; i < _drafts.length; i++)
                          DropdownMenuItem(value: i, child: Text(_drafts[i].name)),
                        const DropdownMenuItem(value: -1, child: Text('Räknas inte med')),
                      ],
                      onChanged: (v) => setState(() => r.target = v == null || v < 0 ? null : _drafts[v]),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

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
            const SizedBox(height: 28),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Har du använt appen förut?', style: t.titleSmall),
                  const SizedBox(height: 4),
                  Text('Hämta din säkerhetskopia, så kommer företag, kategorier, Z-rapportens fält och alla '
                      'registreringar tillbaka. Då behöver du inte gå igenom stegen.', style: t.bodySmall),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(AppIcons.restore),
                    label: const Text('Återställ från säkerhetskopia'),
                    onPressed: _restore,
                  ),
                ]),
              ),
            ),
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
            const SizedBox(height: 16),
            const Text('Företagsform'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final f in CompanyForm.values)
                  ChoiceChip(label: Text(f.label), selected: _form == f, onSelected: (_) => setState(() => _form = f)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _org,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Organisationsnummer (valfritt)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Gatuadress (valfritt)', hintText: 'Storgatan 1'),
            ),
            const SizedBox(height: 8),
            Text('Med organisationsnummer och adress känner appen igen ditt företag på dokumenten.', style: t.bodySmall),
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
      4 => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Raderna på Z-rapporten', style: t.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              'Står det andra namn på din Z-rapport än dina kategorier? Skriv raden som den står på rapporten och välj '
              'vad den ska registreras som. Flera rader kan läggas ihop i samma kategori, t.ex. "Mat avhämtning" och '
              '"Drycka avhämtning" till "Avhämtning".',
            ),
            const SizedBox(height: 8),
            Text('Rader med samma namn som en kategori behöver du inte lägga till. Du kan hoppa över steget och ändra '
                'senare under Inställningar → Fält på Z-rapport.', style: t.bodySmall),
            const SizedBox(height: 12),
            for (final r in _zRules) _zRuleRow(r),
            OutlinedButton.icon(
              icon: const Icon(AppIcons.add),
              label: const Text('Lägg till rad'),
              onPressed: _drafts.isEmpty
                  ? null
                  : () => setState(() => _zRules.add(_ZRuleDraft(_drafts.first))),
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
                icon: const Icon(AppIcons.back),
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

/// A Z-report line typed in the wizard and the category it counts towards
/// (null: not counted). Saved when the wizard finishes.
class _ZRuleDraft {
  final TextEditingController label = TextEditingController();
  CategoryDraft? target;
  _ZRuleDraft(this.target);
}
