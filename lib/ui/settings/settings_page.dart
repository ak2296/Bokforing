import 'package:flutter/material.dart';

import '../app_icons.dart';

import '../../app/app_controller.dart';
import '../../app/pin_lock.dart';
import '../../app/settings_keys.dart';
import '../../domain/license.dart';
import '../../domain/release_notes.dart';
import '../../app/app_update.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/tax_estimate.dart';
import '../../domain/vat.dart';
import '../../notify/reminders.dart';
import '../history_page.dart';
import '../lock/pin_screens.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'accounting_page.dart';
import 'activation_page.dart';
import 'ai_settings_page.dart';
import 'backup_page.dart';
import 'balances_page.dart';
import 'category_editor.dart';
import 'closed_days_page.dart';
import 'cost_types_page.dart';
import 'hints_page.dart';
import 'notification_tile.dart';
import 'storage_page.dart';
import 'guide_reader.dart';
import 'whats_new_page.dart';
import 'z_fields_page.dart';
import '../widgets/blur_overlay.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _search = TextEditingController();

  /// The group shown instead of the home list; null = home.
  String? _openGroup;
  bool _loading = true;
  bool _keepImages = false;
  bool _roundExpenses = false;
  bool _updateCheck = true;
  bool _bioAvailable = false;
  bool _reminders = true;
  bool _notifAllowed = true;
  bool _notesNew = false;
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
    final pinLock = AppScope.read(context).pinLock;
    final p = await repo.profile();
    final form = await repo.companyForm();
    final license = await repo.licenseState();
    final keep = await repo.boolSetting(SettingsKeys.keepImages);
    final roundExpenses = await repo.boolSetting(SettingsKeys.roundExpenses);
    final updateCheck = await repo.boolSetting(SettingsKeys.updateCheck, fallback: true);
    final reminders = await Reminders.enabled(repo);
    final days = await Reminders.days(repo);
    final bio = await pinLock?.biometricAvailable ?? false;
    final notesNew = await notesSeen(repo) < latestNoteId;
    if (!mounted) return;
    setState(() {
      _profile = p;
      _form = form;
      _license = license;
      _keepImages = keep;
      _roundExpenses = roundExpenses;
      _updateCheck = updateCheck;
      _reminders = reminders;
      _reminderDays = days;
      _bioAvailable = bio;
      _notesNew = notesNew;
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
          'redovisning redovisare revisor e-post sms period kvartal halvår år månad',
          ListTile(
            leading: const Icon(AppIcons.mail),
            title: const Text('Redovisning'),
            subtitle: const Text('Hur ofta du lämnar underlag och vem din redovisare är'),
            trailing: const Icon(AppIcons.chevronRight),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountingPage())),
          ),
        ),
        _Entry(
          'ingående balanser bank tillgångar lån skulder balansräkning eget kapital',
          ListTile(
            leading: const Icon(AppIcons.report),
            title: const Text('Ingående balanser'),
            subtitle: const Text('Bank, tillgångar och lån. Behövs för balansräkningen.'),
            trailing: const Icon(AppIcons.chevronRight),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BalancesPage())),
          ),
        ),
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
        _Entry('stängda dagar veckodag helgdag stängt z-rapport saknas',
            nav(AppIcons.calendar, 'Stängda dagar', 'Veckodagar och enstaka dagar utan Z-rapport', () => const ClosedDaysPage())),
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
        _Entry('kostnadstyp egna typer lägg till konto bas',
            nav(AppIcons.rules, 'Kostnadstyper', 'Lägg till egna typer för kostnader som inte passar någon standardtyp', () => const CostTypesPage())),
        _Entry('inlärda fält leverantör summa moms nummer datum',
            nav(AppIcons.rules, 'Inlärda fält', 'Var varje leverantör skriver summa, moms, nummer och datum', () => const HintsPage())),
        _Entry('lagring plats frigör utrymme',
            nav(AppIcons.backup, 'Lagring', 'Hur mycket plats appen tar och hur du frigör plats', () => const StoragePage())),
      ]),
      _Group(AppIcons.notifications, 'Påminnelser', _reminders ? 'På, $_reminderDays dagar före' : 'Av', [
        _Entry('aviseringar tillstånd notis telefon blockerad', NotificationPermissionTile(onChanged: (ok) {
          if (mounted && ok != _notifAllowed) setState(() => _notifAllowed = ok);
        })),
        _Entry(
          'påminnelser notis avisering förfallodag fakturor',
          SwitchListTile(
            secondary: const Icon(AppIcons.notifications),
            title: const Text('Påminn om fakturor som ska betalas'),
            subtitle: Text(_reminders && !_notifAllowed
                ? 'Telefonen blockerar aviseringar från Quee. Tillåt dem ovan, annars kommer ingen påminnelse.'
                : 'En avisering i telefonen före förfallodagen och på förfallodagen.'),
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
              leading: const Icon(AppIcons.notifications, color: Colors.transparent),
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
        if (kSelfUpdate) ...[
          _Entry(
            'uppdatera uppdatering ny version',
            SwitchListTile(
              secondary: const Icon(AppIcons.download),
              title: const Text('Sök efter uppdateringar'),
              subtitle: const Text(
                  'Frågar en gång om dagen om det finns en ny version. Inget annat skickas. Appen uppdateras bara när du trycker på Hämta och installera.'),
              value: _updateCheck,
              onChanged: (v) async {
                await controller.repo.setBoolSetting(SettingsKeys.updateCheck, v);
                if (mounted) setState(() => _updateCheck = v);
              },
            ),
          ),
          _Entry(
            'sök nu uppdatering ny version',
            ListTile(
              leading: const Icon(AppIcons.refresh),
              title: const Text('Sök efter uppdatering nu'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final r = await controller.checkForUpdate(force: true);
                messenger.showSnackBar(SnackBar(
                    content: Text(r == null
                        ? 'Det gick inte att söka just nu. Kontrollera nätverket.'
                        : r
                            ? 'En ny version finns. Du ser den överst på Översikt.'
                            : 'Du har den senaste versionen.')));
              },
            ),
          ),
        ],
        const _Entry(
          'språk svenska',
          ListTile(leading: Icon(AppIcons.language), title: Text('Språk'), subtitle: Text('Svenska')),
        ),
        _Entry('integritet personuppgifter', nav(AppIcons.lock, 'Integritet', '', () => const PrivacyPage())),
        _Entry(
          'rundtur genomgång introduktion hjälp',
          ListTile(
            leading: const Icon(AppIcons.info),
            title: const Text('Visa rundtur'),
            subtitle: const Text('En kort genomgång av appens delar'),
            onTap: () {
              final controller = AppScope.read(context);
              Navigator.of(context).pop();
              controller.tourRequests.value++;
            },
          ),
        ),
        _Entry(
          'nyheter nytt vad är nytt ändringar version uppdatering',
          ListTile(
            leading: const Icon(AppIcons.news),
            title: const Text('Nyheter'),
            subtitle: const Text('Vad som är nytt i varje version'),
            trailing: _notesNew ? Icon(Icons.circle, size: 10, color: AppTheme.pumpkin) : const Icon(AppIcons.chevronRight),
            onTap: () async {
              await markNotesSeen(controller.repo);
              if (mounted) setState(() => _notesNew = false);
              if (!context.mounted) return;
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WhatsNewPage()));
            },
          ),
        ),
        _Entry(
          'användarguide hjälp manual pdf',
          ListTile(
            leading: const Icon(AppIcons.text),
            title: const Text('Användarguide'),
            subtitle: const Text('Hela guiden, med innehåll du kan trycka på'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuideReaderPage())),
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

    _Group? open;
    for (final g in groups) {
      if (g.title == _openGroup) open = g;
    }
    const verksamheten = ['Försäljning', 'Utgifter och dokument', 'Påminnelser'];
    const trygghet = ['Säkerhet', 'Data'];
    const ovrigt = ['Mer'];
    List<_Group> pick(List<String> titles) => [for (final g in groups) if (titles.contains(g.title)) g];

    Widget section(String title, List<_Group> gs) => gs.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(title.toUpperCase(),
                    style: t.labelSmall?.copyWith(color: AppTheme.muted, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
              ),
              Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  for (final (i, g) in gs.indexed) ...[
                    if (i > 0) Divider(height: 1, indent: 72, color: AppTheme.hairline),
                    _HomeRow(g, onTap: () => setState(() => _openGroup = g.title)),
                  ],
                ]),
              ),
            ]),
          );

    final home = <Widget>[
      // The company and the activation at a glance.
      Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _openGroup = 'Företag'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppTheme.seed, Color.lerp(AppTheme.seed, Colors.black, 0.3)!]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(AppIcons.store, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_profile.name.isEmpty ? 'Företagsnamn saknas' : _profile.name, style: t.titleMedium),
                  Text(
                    [
                      if (_form != null) _form!.label,
                      if (_profile.orgNumber.isNotEmpty) 'Org.nr ${_profile.orgNumber}',
                    ].join(' · ').ifEmpty('Tryck för att fylla i'),
                    style: t.bodySmall,
                  ),
                  if (_license != null) ...[
                    const SizedBox(height: 6),
                    Text(licenseStatusText(_license!),
                        style: t.bodySmall?.copyWith(color: AppTheme.seed, fontWeight: FontWeight.w500)),
                  ],
                ]),
              ),
              Icon(AppIcons.chevronRight, color: AppTheme.muted),
            ]),
          ),
        ),
      ),
      // Bright or dark: one row with a sliding switch (sun / moon).
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: controller.themeMode,
              builder: (context, mode, _) {
                final dark = mode == ThemeMode.dark || (mode == ThemeMode.system && AppTheme.dark);
                return Row(children: [
                  Icon(dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined, size: 22, color: AppTheme.seed),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Utseende', style: t.titleSmall),
                      if (mode == ThemeMode.system)
                        Text('Följer telefonen', style: t.bodySmall)
                      else
                        GestureDetector(
                          onTap: () => controller.setThemeMode(ThemeMode.system),
                          child: Text('Följ telefonen', style: t.bodySmall?.copyWith(color: AppTheme.seed, fontWeight: FontWeight.w500)),
                        ),
                    ]),
                  ),
                  _ThemeSwitch(dark: dark, onChanged: (d) => controller.setThemeMode(d ? ThemeMode.dark : ThemeMode.light)),
                ]);
              },
            ),
          ),
        ),
      ),
      section('Verksamheten', pick(verksamheten)),
      section('Trygghet', pick(trygghet)),
      section('Övrigt', pick(ovrigt)),
    ];

    return PopScope(
      canPop: open == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _openGroup = null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(open?.title ?? 'Inställningar'),
          leading: open == null
              ? null
              : IconButton(icon: const Icon(AppIcons.back), onPressed: () => setState(() => _openGroup = null)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  if (open == null) ...[
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
                    const SizedBox(height: 16),
                  ],
                  if (open == null && query.isNotEmpty)
                    if (hits.isEmpty)
                      const EmptyState(icon: AppIcons.search, text: 'Ingen inställning matchar sökningen.')
                    else
                      Card(child: Column(children: hits))
                  else if (open != null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                      child: Text(open.summary, style: t.bodySmall),
                    ),
                    Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: Column(children: [for (final e in open.entries) e.child]),
                    ),
                  ] else
                    ...home,
                ],
              ),
      ),
    );
  }
}

/// A row on the settings home: a tinted icon, the name, what is set now, and an arrow.
class _HomeRow extends StatelessWidget {
  final _Group group;
  final VoidCallback onTap;
  const _HomeRow(this.group, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          IconTile(group.icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(group.title, style: t.titleSmall),
              Text(group.summary, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Icon(AppIcons.chevronRight, color: AppTheme.muted, size: 20),
        ]),
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
  TaxMode _taxMode = TaxMode.percent;
  final _taxPercent = TextEditingController();
  final _taxAmount = TextEditingController();
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
    final tax = await repo.taxEstimate();
    if (!mounted) return;
    setState(() {
      _taxMode = tax.mode;
      _taxPercent.text = '${tax.percentTenths ~/ 10}${tax.percentTenths % 10 == 0 ? '' : ',${tax.percentTenths % 10}'}';
      _taxAmount.text = tax.yearlyAmount.isZero ? '' : tax.yearlyAmount.toInput();
      // Locked while the activation or trial applies; after a change the fields
      // are open again so the owner can put the company back.
      _locked = license.status == LicenseStatus.active && (license.license?.locksCompany ?? false);
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
            if (_form == CompanyForm.aktiebolag) ...[
              const SizedBox(height: 8),
              Text('Under Resultat visas 20,6 % bolagsskatt som en uppskattning att lägga undan.',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            if (_form == CompanyForm.enskildFirma) ...[
              const SizedBox(height: 16),
              const Text('Uppskattad skatt'),
              const SizedBox(height: 4),
              Text('Visas som "Att lägga undan" under Resultat på Månad och År. Det är din egen uppskattning, ingen skatteberäkning.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              SegmentedButton<TaxMode>(
                segments: const [
                  ButtonSegment(value: TaxMode.percent, label: Text('Procent')),
                  ButtonSegment(value: TaxMode.amount, label: Text('Belopp per år')),
                ],
                selected: {_taxMode},
                onSelectionChanged: (s) => setState(() => _taxMode = s.first),
              ),
              const SizedBox(height: 8),
              if (_taxMode == TaxMode.percent)
                TextField(
                  controller: _taxPercent,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Procent av resultatet', suffixText: '%', hintText: 't.ex. 30'),
                )
              else
                TextField(
                  controller: _taxAmount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Preliminär skatt per år', suffixText: 'kr', hintText: 't.ex. 36000'),
                ),
            ],
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
                child: Text('Årsrapporter kommer att grupperas annorlunda. Sparade dokument ändras inte.',
                    style: TextStyle(color: AppTheme.warning)),
              ),
            const SizedBox(height: 24),
            Text('Mina företagsnamn', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Andra namn som ditt företag har på dokumenten. De blir aldrig leverantör.',
                style: Theme.of(context).textTheme.bodySmall),
            if (_ownNames.isNotEmpty) const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final n in _ownNames) InputChip(label: Text(n), onDeleted: () => _removeName(n)),
              ],
            ),
            const SizedBox(height: 14),
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
                final pct = double.tryParse(_taxPercent.text.trim().replaceAll(',', '.'));
                await controller.repo.setTaxEstimate(
                    _taxMode,
                    pct == null ? 300 : (pct * 10).round().clamp(0, 1000).toInt(),
                    Money.parse(_taxAmount.text) ?? Money.zero);
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
        final leave = await showBlurDialog<bool>(
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

/// A sliding switch with a sun on the left and a moon on the right: tap to flip
/// between bright and dark.
class _ThemeSwitch extends StatelessWidget {
  final bool dark;
  final ValueChanged<bool> onChanged;
  const _ThemeSwitch({required this.dark, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const w = 84.0, h = 40.0, knob = 32.0;
    return Semantics(
      toggled: dark,
      label: 'Mörkt utseende',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!dark),
        child: SizedBox(
          height: 48,
          child: Center(
            child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(h / 2),
            color: AppTheme.switchTrack(dark),
            border: Border.all(color: AppTheme.hairline),
          ),
          child: Stack(alignment: Alignment.center, children: [
            Positioned(left: 10, child: Icon(Icons.light_mode, size: 17, color: dark ? AppTheme.switchIdle : AppTheme.switchSun)),
            Positioned(right: 10, child: Icon(Icons.dark_mode, size: 17, color: dark ? AppTheme.switchMoon : AppTheme.switchIdle)),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              left: dark ? w - knob - 4 : 4,
              child: Container(
                width: knob,
                height: knob,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dark ? AppTheme.switchKnobDark : Colors.white,
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1))],
                ),
                child: Icon(dark ? Icons.dark_mode : Icons.light_mode, size: 18, color: dark ? Colors.white : AppTheme.switchSun),
              ),
            ),
          ]),
            ),
          ),
        ),
      ),
    );
  }
}
