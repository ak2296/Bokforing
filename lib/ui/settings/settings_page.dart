import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/settings_keys.dart';
import '../../domain/models.dart';
import '../../domain/vat.dart';
import '../history_page.dart';
import 'ai_settings_page.dart';
import 'backup_page.dart';
import 'category_editor.dart';
import 'invoice_fields_page.dart';
import 'z_fields_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loading = true;
  bool _keepImages = false;
  BusinessProfile _profile = const BusinessProfile();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  Future<void> _load() async {
    final repo = AppScope.read(context).repo;
    final p = await repo.profile();
    final keep = await repo.boolSetting(SettingsKeys.keepImages);
    if (!mounted) return;
    setState(() {
      _profile = p;
      _keepImages = keep;
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
                  leading: const Icon(Icons.store_outlined),
                  title: Text(_profile.name.isEmpty ? 'Företagsnamn saknas' : _profile.name),
                  subtitle: Text([
                    if (_profile.orgNumber.isNotEmpty) 'Org.nr ${_profile.orgNumber}',
                    if (_profile.address.isNotEmpty) _profile.address,
                  ].join(' · ').ifEmpty('Tryck för att ändra')),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompanyPage()));
                    _load();
                  },
                ),
                header('Försäljning'),
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Försäljningskategorier'),
                  subtitle: const Text('Namn och momssats per kategori'),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const CategoriesPage())),
                ),
                ListTile(
                  leading: const Icon(Icons.receipt_outlined),
                  title: const Text('Fält på Z-rapport'),
                  subtitle: const Text('Vad varje rad på Z-rapporten registreras som'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ZFieldsPage())),
                ),
                header('Dokument'),
                ListTile(
                  leading: const Icon(Icons.rule_outlined),
                  title: const Text('Fält på fakturor'),
                  subtitle: const Text('Vilket datum, vilken summa och vilken moms som används'),
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InvoiceFieldsPage())),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.image_outlined),
                  title: const Text('Behåll originalbilder'),
                  subtitle: const Text('Av: bilden tas bort efter att du godkänt uppgifterna. Texten sparas ändå.'),
                  value: _keepImages,
                  onChanged: (v) async {
                    await AppScope.read(context).repo.setBoolSetting(SettingsKeys.keepImages, v);
                    setState(() => _keepImages = v);
                  },
                ),
                header('Data'),
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Säkerhetskopiering'),
                  subtitle: const Text('Exportera eller importera säkerhetskopia'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BackupPage())),
                ),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Historik'),
                  subtitle: const Text('Alla registreringar med status'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryPage())),
                ),
                header('Förbättrad analys (valfritt)'),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('Förbättrad analys online'),
                  subtitle: const Text('Av som standard. Skickar en bild till Google bara när du godkänner det.'),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const AiSettingsPage())),
                ),
                header('App'),
                const ListTile(
                  leading: Icon(Icons.language),
                  title: Text('Språk'),
                  subtitle: Text('Svenska'),
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Integritet'),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const PrivacyPage())),
                ),
                const AboutListTile(
                  icon: Icon(Icons.info_outline),
                  applicationName: 'Bokföringsassistent',
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
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      AppScope.read(context).repo.profile().then((p) {
        if (!mounted) return;
        setState(() {
          _name.text = p.name;
          _org.text = p.orgNumber;
          _address.text = p.address;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Företag')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Företagsnamn')),
            const SizedBox(height: 12),
            TextField(
                controller: _org,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Organisationsnummer (valfritt)')),
            const SizedBox(height: 12),
            TextField(
                controller: _address,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Adress (valfritt)')),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                final controller = AppScope.read(context);
                await controller.repo.saveProfile(
                    BusinessProfile(name: _name.text, orgNumber: _org.text, address: _address.text));
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
