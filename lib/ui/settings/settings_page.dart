import 'package:flutter/material.dart';

import '../app_icons.dart';

import '../../app/app_controller.dart';
import '../../app/pin_lock.dart';
import '../../app/settings_keys.dart';
import '../../domain/license.dart';
import '../../domain/models.dart';
import '../../domain/vat.dart';
import '../../notify/reminders.dart';
import '../history_page.dart';
import '../lock/pin_screens.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'activation_page.dart';
import 'ai_settings_page.dart';
import 'backup_page.dart';
import 'category_editor.dart';
import 'hints_page.dart';
import 'storage_page.dart';
import 'user_guide.dart';
import 'z_fields_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _search = TextEditingController();
  bool _loading = true;
  bool _keepImages = false;
  bool _roundExpenses = false;
  bool _bioAvailable = false;
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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = AppScope.read(context).repo;
    final p = await repo.profile();
    final form = await repo.companyForm();
    final license = await repo.licenseState();
    final keep = await repo.boolSetting(SettingsKeys.keepImages);
    final roundExpenses = await repo.boolSetting(SettingsKeys.roundExpenses);
    final reminders = await Reminders.enabled(repo);
    final days = await Reminders.days(repo);
    final bio = await AppScope.read(context).pinLock?.biometricAvailable ?? false;
    if (!mounted) return;
    setState(() {
      _profile = p;
      _form = form;
      _license = license;
      _keepImages = keep;
      _roundExpenses = roundExpenses;
      _reminders = reminders;
      _reminderDays = days;
      _bioAvailable = bio;
      _loading = false;
    });
  }

  Future<void> _turnOnLock(PinLock lock) async {
    final backupOff = !(await AppScope.read(context).autoBackup?.active() ?? false);
    if (!mounted) return;
    await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => PinSetupPage(lock: lock, backupOff: backupOff)));
  }

  Future<void> _turnOffLock(PinLock lock) async {
    if (await confirmPin(context, lock, title: 'Stäng av PIN-kod')) await lock.clear();
  }

  Future<void> _changePin(PinLock lock) async {
    if (!await confirmPin(context, lock, title: 'Byt PIN-kod') || !mounted) return;
    await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => PinSetupPage(lock: lock, backupOff: false)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pinLock = AppScope.read(context).pinLock;
    final controller = AppScope.read(context);
    final query = _search.text.trim().toLowerCase();

    Widget nav(IconData icon, String title, String subtitle, Widget Function() page, {bool reload = false}) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle.isEmpty ? null : Text(subtitle),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page()));
            if (reload) _load();
          },
        );

    final groups = <_Group>[
      _Group(AppIcons.settings, 'Utseende', 'Ljust, mörkt eller som telefonen', [
        _Entry(
          'ljust mörkt dark mode tema utseende färg',
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: controller.themeMode,
              builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('Auto')),
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Ljust')),
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Mörkt')),
                ],
                selected: {mode},
                showSelectedIcon: false,
                onSelectionChanged: (s) => controller.setThemeMode(s.first),
              ),
            ),
          ),
        ),
      ]),
      _Group(AppIcons.store, 'Företag', _profile.name.isEmpty ? 'Företagsnamn saknas' : _profile.name, [
        _Entry(
          'företag namn organisationsnummer adress bolagsform',
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
        ),
        _Entry(
          'aktivering licens kod',
          ListTile(
            leading: const Icon(AppIcons.lock),
            title: const Text('Aktivering'),
            subtitle: Text(_license == null ? '' : licenseStatusText(_license!)),
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ActivationPage()));
              _load();
            },
          ),
        ),
      ]),
      _Group(AppIcons.register, 'Försäljning', 'Kategorier och Z-rapportens fält', [
        _Entry('försäljningskategorier moms momssats kategori',
            nav(AppIcons.category, 'Försäljningskategorier', 'Namn och momssats per kategori', () => const CategoriesPage())),
        _Entry('z-rapport fält rader',
            nav(AppIcons.rules, 'Fält på Z-rapport', 'Vad varje rad på Z-rapporten registreras som', () => const ZFieldsPage())),
      ]),
      _Group(AppIcons.expenses, 'Utgifter och dokument', 'Avrunda, originalbilder, inlärda fält, lagring', [
        _Entry(
          'avrunda utgifter hela kronor',
          SwitchListTile(
            secondary: const Icon(AppIcons.payments),
            title: const Text('Avrunda utgifter till hela kronor'),
            subtitle: const Text(
                'Listor och rapporter visar och summerar summa och moms i hela kronor. Det sparade beloppet ändras inte.'),
            value: _roundExpenses,
            onChanged: (v) async {
              await controller.repo.setBoolSetting(SettingsKeys.roundExpenses, v);
              controller.dataChanged();
              if (mounted) setState(() => _roundExpenses = v);
            },
          ),
        ),
        _Entry(
          'originalbilder behåll bild foto',
          SwitchListTile(
            secondary: const Icon(AppIcons.image),
            title: const Text('Behåll originalbilder'),
            subtitle: const Text('Av: bilden tas bort efter att du godkänt uppgifterna. Texten sparas ändå.'),
            value: _keepImages,
            onChanged: (v) async {
              await controller.repo.setBoolSetting(SettingsKeys.keepImages, v);
              setState(() => _keepImages = v);
            },
          ),
        ),
        _Entry('inlärda fält leverantör summa moms nummer datum',
            nav(AppIcons.rules, 'Inlärda fält', 'Var varje leverantör skriver summa, moms, nummer och datum', () => const HintsPage())),
        _Entry('lagring plats frigör utrymme',
            nav(AppIcons.backup, 'Lagring', 'Hur mycket plats appen tar och hur du frigör plats', () => const StoragePage())),
      ]),
      _Group(AppIcons.notifications, 'Påminnelser', _reminders ? 'På, $_reminderDays dagar före' : 'Av', [
        _Entry(
          'påminnelser notis avisering förfallodag fakturor',
          SwitchListTile(
            secondary: const Icon(AppIcons.notifications),
            title: const Text('Påminn om fakturor som ska betalas'),
            subtitle: const Text('En avisering i telefonen före förfallodagen och på förfallodagen.'),
            value: _reminders,
            onChanged: (v) async {
              await controller.repo.setBoolSetting(Reminders.enabledKey, v);
              if (v) await controller.reminders?.requestPermission();
              controller.dataChanged();
              if (mounted) setState(() => _reminders = v);
            },
          ),
        ),
        if (_reminders)
          _Entry(
            'påminn dagar före förfallodagen',
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
                  await controller.repo.setSetting(Reminders.daysKey, '$v');
                  controller.dataChanged();
                  if (mounted) setState(() => _reminderDays = v);
                },
              ),
            ),
          ),
      ]),
      if (pinLock != null)
        _Group(AppIcons.lock, 'Säkerhet', pinLock.enabled ? 'PIN-kod på' : 'PIN-kod av', [
          _Entry(
            'pin pinkod lås fingeravtryck säkerhet biometri',
            ListenableBuilder(
              listenable: pinLock,
              builder: (context, _) => Column(children: [
                SwitchListTile(
                  secondary: const Icon(AppIcons.lock),
                  title: const Text('Lås appen med PIN-kod'),
                  subtitle: const Text('PIN-koden frågas när appen öppnas och efter två minuter i bakgrunden.'),
                  value: pinLock.enabled,
                  onChanged: (v) => v ? _turnOnLock(pinLock) : _turnOffLock(pinLock),
                ),
                if (pinLock.enabled && _bioAvailable)
                  SwitchListTile(
                    secondary: const Icon(Icons.fingerprint),
                    title: const Text('Fingeravtryck'),
                    subtitle: const Text('Lås upp med fingeravtryck. PIN-koden finns kvar om det inte fungerar.'),
                    value: pinLock.biometricEnabled,
                    onChanged: (v) async {
                      final ok = await pinLock.setBiometric(v);
                      if (!ok && v && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Fingeravtrycket kunde inte bekräftas. Inget ändrades.')));
                      }
                    },
                  ),
                if (pinLock.enabled)
                  ListTile(
                    leading: const SizedBox(width: 24),
                    title: const Text('Byt PIN-kod'),
                    onTap: () => _changePin(pinLock),
                  ),
              ]),
            ),
          ),
        ]),
      _Group(AppIcons.backup, 'Data', 'Säkerhetskopia och historik', [
        _Entry('säkerhetskopiering backup exportera importera',
            nav(AppIcons.backup, 'Säkerhetskopiering', 'Exportera eller importera säkerhetskopia', () => const BackupPage())),
        _Entry('historik registreringar status',
            nav(AppIcons.history, 'Historik', 'Alla registreringar med status', () => const HistoryPage())),
      ]),
      _Group(AppIcons.info, 'Mer', 'Analys online, integritet, guide, om appen', [
        _Entry('förbättrad analys online google ai',
            nav(AppIcons.ai, 'Förbättrad analys online', 'Av som standard. Skickar en bild till Google bara när du godkänner det.', () => const AiSettingsPage())),
        const _Entry(
          'språk svenska',
          ListTile(leading: Icon(AppIcons.language), title: Text('Språk'), subtitle: Text('Svenska')),
        ),
        _Entry('integritet personuppgifter', nav(AppIcons.lock, 'Integritet', '', () => const PrivacyPage())),
        _Entry(
          'användarguide hjälp manual pdf',
          ListTile(
            leading: const Icon(AppIcons.text),
            title: const Text('Användarguide'),
            subtitle: const Text('Hela guiden som PDF, öppnas i telefonens PDF-läsare'),
            onTap: () => openUserGuide(context),
          ),
        ),
        const _Entry(
          'om appen version',
          AboutListTile(
            icon: Icon(AppIcons.info),
            applicationName: 'Quee',
            applicationVersion: '0.2.0',
            aboutBoxChildren: [
              Text('Lokal bokföringsassistent för småföretag i Sverige. '
                  'Beräkningarna är ett stöd och ersätter inte en fullständig bokföring eller momsdeklaration.'),
            ],
            child: Text('Om appen'),
          ),
        ),
      ]),
    ];

    final hits = [
      for (final g in groups)
        for (final e in g.entries)
          if (query.isNotEmpty && ('${g.title} ${e.keywords}').toLowerCase().contains(query)) e.child,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Inställningar')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Sök i inställningar',
                    prefixIcon: const Icon(AppIcons.search),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Rensa',
                            icon: const Icon(AppIcons.close),
                            onPressed: () => setState(_search.clear),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                if (query.isNotEmpty)
                  if (hits.isEmpty)
                    const EmptyState(icon: AppIcons.search, text: 'Ingen inställning matchar sökningen.')
                  else
                    Card(child: Column(children: hits))
                else
                  for (final g in groups)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            key: PageStorageKey(g.title),
                            leading: IconTile(g.icon),
                            title: Text(g.title, style: t.titleSmall),
                            subtitle: Text(g.summary, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                            children: [for (final e in g.entries) e.child],
                          ),
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}

class _Group {
  final IconData icon;
  final String title;
  final String summary;
  final List<_Entry> entries;
  const _Group(this.icon, this.title, this.summary, this.entries);
}

class _Entry {
  /// What the search looks in, besides the group's name.
  final String keywords;
  final Widget child;
  const _Entry(this.keywords, this.child);
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
              Padding(
                padding: const EdgeInsets.only(top: 8),
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
