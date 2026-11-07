import 'package:flutter/material.dart';

import '../app_icons.dart';

import '../../app/app_controller.dart';
import '../../app/settings_keys.dart';
import '../../domain/license.dart';
import '../../domain/models.dart';
import '../../domain/vat.dart';
import '../../notify/reminders.dart';
import '../history_page.dart';
import '../theme.dart';
import 'activation_page.dart';
import 'ai_settings_page.dart';
import 'backup_page.dart';
import 'category_editor.dart';
import 'storage_page.dart';
import 'z_fields_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loading = true;
  bool _keepImages = false;
  bool _reminders = true;
  int _reminderDays = Reminders.defaultDays;
  BusinessProfile _profile = const BusinessProfile();
  CompanyForm? _form;
  LicenseState? _license;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  Future<void> _load() async {
    final repo = AppScope.read(context).repo;
    final p = await repo.profile();
    final form = await repo.companyForm();
    final license = await repo.licenseState();
    final keep = await repo.boolSetting(SettingsKeys.keepImages);
    final reminders = await Reminders.enabled(repo);
    final days = await Reminders.days(repo);
    if (!mounted) return;
    setState(() {
      _profile = p;
      _form = form;
      _license = license;
      _keepImages = keep;
      _reminders = reminders;
      _reminderDays = days;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget header(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(s, style: t.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Inställningar')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                header('Företag'),
                ListTile(
                  leading: const Icon(AppIcons.store),
                  title: Text(_profile.name.isEmpty ? 'Företagsnamn saknas' : _profile.name),
                  subtitle: Text([
                    if (_form != null) _form!.label,
                    if (_profile.orgNumber.isNotEmpty) 'Org.nr ${_profile.orgNumber}',
                    if (_profile.address.isNotEmpty) _profile.address,
                  ].join(' · ').ifEmpty('Tryck för att ändra')),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompanyPage()));
                    _load();
                  },
                ),
                ListTile(
                  leading: const Icon(AppIcons.lock),
                  title: const Text('Aktivering'),
                  subtitle: Text(_license == null ? '' : licenseStatusText(_license!)),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ActivationPage()));
                    _load();
                  },
                ),
                header('Försäljning'),
                ListTile(
                  leading: const Icon(AppIcons.category),
                  title: const Text('Försäljningskategorier'),
                  subtitle: const Text('Namn och momssats per kategori'),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const CategoriesPage())),
                ),
                ListTile(
                  leading: const Icon(AppIcons.rules),
                  title: const Text('Fält på Z-rapport'),
                  subtitle: const Text('Vad varje rad på Z-rapporten registreras som'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ZFieldsPage())),
                ),
                header('Dokument'),
                SwitchListTile(
                  secondary: const Icon(AppIcons.image),
                  title: const Text('Behåll originalbilder'),
                  subtitle: const Text('Av: bilden tas bort efter att du godkänt uppgifterna. Texten sparas ändå.'),
                  value: _keepImages,
                  onChanged: (v) async {
                    await AppScope.read(context).repo.setBoolSetting(SettingsKeys.keepImages, v);
                    setState(() => _keepImages = v);
                  },
                ),
                ListTile(
                  leading: const Icon(AppIcons.backup),
                  title: const Text('Lagring'),
                  subtitle: const Text('Hur mycket plats appen tar och hur du frigör plats'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StoragePage())),
                ),
                header('Påminnelser'),
                SwitchListTile(
                  secondary: const Icon(AppIcons.notifications),
                  title: const Text('Påminn om fakturor som ska betalas'),
                  subtitle: const Text('En avisering i telefonen före förfallodagen och på förfallodagen.'),
                  value: _reminders,
                  onChanged: (v) async {
                    final controller = AppScope.read(context);
                    await controller.repo.setBoolSetting(Reminders.enabledKey, v);
                    if (v) await controller.reminders?.requestPermission();
                    controller.dataChanged();
                    if (mounted) setState(() => _reminders = v);
                  },
                ),
                if (_reminders)
                  ListTile(
                    leading: const SizedBox(width: 24),
                    title: const Text('Påminn dagar före förfallodagen'),
                    trailing: DropdownButton<int>(
                      value: _reminderDays,
                      items: [
                        for (final d in const [1, 2, 3, 5, 7, 10]) DropdownMenuItem(value: d, child: Text('$d')),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        final controller = AppScope.read(context);
                        await controller.repo.setSetting(Reminders.daysKey, '$v');
                        controller.dataChanged();
                        if (mounted) setState(() => _reminderDays = v);
                      },
                    ),
                  ),
                header('Data'),
                ListTile(
                  leading: const Icon(AppIcons.backup),
                  title: const Text('Säkerhetskopiering'),
                  subtitle: const Text('Exportera eller importera säkerhetskopia'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BackupPage())),
                ),
                ListTile(
                  leading: const Icon(AppIcons.history),
                  title: const Text('Historik'),
                  subtitle: const Text('Alla registreringar med status'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryPage())),
                ),
                header('Förbättrad analys (valfritt)'),
                ListTile(
                  leading: const Icon(AppIcons.ai),
                  title: const Text('Förbättrad analys online'),
                  subtitle: const Text('Av som standard. Skickar en bild till Google bara när du godkänner det.'),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const AiSettingsPage())),
                ),
                header('App'),
                const ListTile(
                  leading: Icon(AppIcons.language),
                  title: Text('Språk'),
                  subtitle: Text('Svenska'),
                ),
                ListTile(
                  leading: const Icon(AppIcons.lock),
                  title: const Text('Integritet'),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const PrivacyPage())),
                ),
                const AboutListTile(
                  icon: Icon(AppIcons.info),
                  applicationName: 'Bokföring',
                  applicationVersion: '0.2.0',
                  aboutBoxChildren: [
                    Text('Lokal bokföringsassistent för småföretag i Sverige. '
                        'Beräkningarna är ett stöd och ersätter inte en fullständig bokföring eller momsdeklaration.'),
                  ],
                  child: Text('Om appen'),
                ),
              ],
            ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class CompanyPage extends StatefulWidget {
  const CompanyPage({super.key});

  @override
  State<CompanyPage> createState() => _CompanyPageState();
}

class _CompanyPageState extends State<CompanyPage> {
  final _name = TextEditingController();
  final _org = TextEditingController();
  final _address = TextEditingController();
  final _newName = TextEditingController();
  bool _loaded = false;
  CompanyForm? _form;
  int _fiscalMonth = 1;
  int _savedFiscalMonth = 1;
  List<String> _ownNames = const [];

  /// A customer's code fixes the company name and org number.
  bool _locked = false;

  static const _months = [
    'Januari', 'Februari', 'Mars', 'April', 'Maj', 'Juni', 'Juli', 'Augusti', 'September', 'Oktober', 'November',
    'December',
  ];

  String _fiscalLabel(int start) => '${_months[start - 1]} – ${_months[(start + 10) % 12]}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  Future<void> _load() async {
    final repo = AppScope.read(context).repo;
    final p = await repo.profile();
    final form = await repo.companyForm();
    final month = await repo.fiscalStartMonth();
    final names = await repo.ownNames();
    final license = await repo.licenseState();
    if (!mounted) return;
    setState(() {
      _locked = license.license?.locksCompany ?? false;
      _name.text = p.name;
      _org.text = p.orgNumber;
      _address.text = p.address;
      _form = form;
      _fiscalMonth = month;
      _savedFiscalMonth = month;
      _ownNames = names;
    });
  }

  Future<void> _addName() async {
    final repo = AppScope.read(context).repo;
    await repo.addOwnName(_newName.text);
    final names = await repo.ownNames();
    if (!mounted) return;
    setState(() {
      _newName.clear();
      _ownNames = names;
    });
  }

  Future<void> _removeName(String name) async {
    final repo = AppScope.read(context).repo;
    await repo.removeOwnName(name);
    final names = await repo.ownNames();
    if (mounted) setState(() => _ownNames = names);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Företag')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(controller: _name, enabled: !_locked, decoration: const InputDecoration(labelText: 'Företagsnamn')),
            const SizedBox(height: 12),
            TextField(
                controller: _org,
                enabled: !_locked,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Organisationsnummer (valfritt)')),
            const SizedBox(height: 12),
            TextField(
                controller: _address,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Adress (valfritt)', hintText: 'Storgatan 1')),
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
            DropdownButtonFormField<int>(
              initialValue: _fiscalMonth,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Räkenskapsår'),
              items: [
                for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(_fiscalLabel(m))),
              ],
              onChanged: (v) => setState(() => _fiscalMonth = v ?? 1),
            ),
            if (_fiscalMonth != _savedFiscalMonth)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Årsrapporter kommer att grupperas annorlunda. Sparade papper ändras inte.',
                    style: TextStyle(color: AppTheme.warning)),
              ),
            const SizedBox(height: 16),
            const Text('Mina företagsnamn'),
            const SizedBox(height: 4),
            Text('Andra namn som ditt företag har på papperen. De blir aldrig leverantör.',
                style: Theme.of(context).textTheme.bodySmall),
            Wrap(
              spacing: 8,
              children: [
                for (final n in _ownNames) InputChip(label: Text(n), onDeleted: () => _removeName(n)),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newName,
                    decoration: const InputDecoration(labelText: 'Lägg till namn', isDense: true),
                  ),
                ),
                IconButton(tooltip: 'Lägg till namn', icon: const Icon(AppIcons.add), onPressed: _addName),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                final controller = AppScope.read(context);
                await controller.repo.saveProfile(
                    BusinessProfile(name: _name.text, orgNumber: _org.text, address: _address.text));
                if (_form != null) await controller.repo.setCompanyForm(_form!);
                await controller.repo.setFiscalStartMonth(_fiscalMonth);
                controller.dataChanged();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Spara'),
            ),
          ],
        ),
      );
}

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  List<CategoryDraft>? _drafts;
  List<VatRate> _rates = const [];
  bool _dirty = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_drafts == null) _load();
  }

  Future<void> _load() async {
    final repo = AppScope.read(context).repo;
    final cats = await repo.categories();
    final rates = await repo.vatRates();
    if (!mounted) return;
    setState(() {
      _drafts = cats.map(CategoryDraft.from).toList();
      _rates = rates;
    });
  }

  Future<void> _save() async {
    final controller = AppScope.read(context);
    final drafts = _drafts!;
    await controller.repo.saveCategories([for (var i = 0; i < drafts.length; i++) drafts[i].toCategory(i)]);
    controller.dataChanged();
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kategorierna har sparats.')));
  }

  @override
  Widget build(BuildContext context) {
    final drafts = _drafts;
    final missingVat = drafts?.any((d) => d.vat == null) ?? false;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Osparade ändringar'),
            content: const Text('Vill du lämna utan att spara?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Stanna')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Lämna')),
            ],
          ),
        );
        if (leave == true && context.mounted) {
          setState(() => _dirty = false);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Försäljningskategorier')),
        body: drafts == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('Kategorierna styr kolumnerna i månadsrapporten. Ändringar påverkar inte redan sparade dagar.'),
                  const SizedBox(height: 12),
                  const VatGuidanceCard(),
                  const SizedBox(height: 8),
                  CategoryListEditor(
                    drafts: drafts,
                    rates: _rates,
                    onChanged: () => setState(() => _dirty = true),
                    onAddRate: (r) async {
                      await AppScope.read(context).repo.addVatRate(r);
                      setState(() => _rates = {..._rates, r}.toList()..sort());
                    },
                  ),
                  const SizedBox(height: 20),
                  if (missingVat) const Text('Välj momssats för alla kategorier innan du sparar.'),
                  FilledButton(
                    onPressed: _dirty && !missingVat ? _save : null,
                    child: const Text('Spara'),
                  ),
                ],
              ),
      ),
    );
  }
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Integritet')),
        body: const SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Text(
            'Dina uppgifter stannar i telefonen.\n\n'
            '• Fakturor, Z-rapporter och bokföringsuppgifter sparas bara i appens lokala databas.\n'
            '• Texten i dokumenten läses av direkt i telefonen. Inga bilder eller uppgifter skickas till någon server.\n'
            '• Appen innehåller ingen reklam, ingen statistikinsamling och inga spårningsverktyg.\n'
            '• Säkerhetskopior skapas bara när du själv väljer det, och du väljer var filen sparas.\n\n'
            'Undantag som du själv väljer: "Förbättrad analys online" är avstängd tills du aktiverar den och klistrar in en egen API-nyckel. '
            'Även då frågar appen varje gång innan en bild skickas till Google, och bara den bilden skickas.',
          ),
        ),
      );
}
