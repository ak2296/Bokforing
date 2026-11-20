import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_controller.dart';
import '../../data/vat_manual_store.dart';
import '../../domain/ledger.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/report_period.dart';
import '../../export/moms_xml.dart';
import '../app_icons.dart';
import '../settings/settings_page.dart';
import '../theme.dart';
import 'report_hero.dart';

const _infoUrl = 'https://skatteverket.se/foretag/moms/deklareramoms/lamnamomsdeklarationviafilietjansten.4.2fb39afe18dabf1e4d223cc.html';

String _kr(int v) => Money.kr(v).format(unit: false, compact: true);

/// "Momsfil till Skatteverket": the momsdeklaration of the period as the XML file the
/// e-service takes under "Deklarera via fil". Quee sends nothing: the owner saves
/// the file, uploads it at Skatteverket, checks it there and signs with e-legitimation.
/// What Quee cannot know (EU trade, import and so on) the owner can type under
/// "Egna uppgifter"; Quee does not check those.
class MomsFilePage extends StatefulWidget {
  final ReportPeriod period;
  final Ledger ledger;
  final BusinessProfile profile;
  const MomsFilePage({super.key, required this.period, required this.ledger, required this.profile});

  @override
  State<MomsFilePage> createState() => _MomsFilePageState();
}

class _MomsFilePageState extends State<MomsFilePage> {
  late BusinessProfile _profile = widget.profile;
  Map<int, int> _manual = {};
  bool _loaded = false;
  bool _sure = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await loadVatManual(AppScope.read(context).repo, widget.period.fileTag);
    if (mounted) {
      setState(() {
        _manual = m;
        _loaded = true;
      });
    }
  }

  Future<void> _editManual() async {
    final result = await Navigator.of(context).push<Map<int, int>>(MaterialPageRoute(builder: (_) => VatManualPage(initial: _manual)));
    if (result == null || !mounted) return;
    await saveVatManual(AppScope.read(context).repo, widget.period.fileTag, result);
    if (mounted) {
      setState(() {
        _manual = result;
        _sure = false;
      });
    }
  }

  Future<void> _editCompany() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CompanyPage()));
    if (!mounted) return;
    final prof = await AppScope.read(context).repo.profile();
    if (mounted) setState(() => _profile = prof);
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Det gick inte: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(VatReturn r) => _run(() async {
        final saved = await FilePicker.saveFile(dialogTitle: 'Spara momsfil', fileName: r.fileName, bytes: r.toBytes());
        if (saved != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Momsfilen har sparats. Lämna in den hos Skatteverket.')));
        }
      });

  Future<void> _share(VatReturn r) => _run(() async {
        final dir = await getTemporaryDirectory();
        final file = File(p.join(dir.path, r.fileName));
        await file.writeAsBytes(r.toBytes(), flush: true);
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/xml')], subject: 'Momsfil ${widget.period.title}'));
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final period = widget.period;
    final supported = VatReturn.supports(period.kind);
    final org = VatReturn.normaliseOrgNr(_profile.orgNumber);
    final ready = supported && org != null && _loaded;
    final r = ready ? VatReturn.fromLedger(widget.ledger, period, org, manual: _manual) : null;
    final canSend = r != null && !_busy && (_manual.isEmpty || _sure);
    return Scaffold(
      appBar: AppBar(title: const Text('Momsfil till Skatteverket')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          ReportHero(
            color: AppTheme.accounting,
            label: 'Momsdeklaration',
            value: period.title,
            chips: [('Org.nr', org ?? 'saknas'), ('Period', r?.period ?? '–')],
          ),
          if (!supported) ...[
            const SizedBox(height: 10),
            const _Notice('Momsdeklarationen lämnas per månad, kvartal eller år. Välj en av dem högst upp på rapportsidan.'),
          ] else if (org == null) ...[
            const SizedBox(height: 10),
            _Notice('Företagets organisationsnummer saknas eller är fel. Skatteverket kräver tio siffror.',
                button: 'Fyll i företagets uppgifter', onPressed: _editCompany),
          ] else if (r != null) ...[
            const SizedBox(height: 10),
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final (i, b) in r.boxes.indexed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: b.$1 == '49' ? AppTheme.accounting.withValues(alpha: 0.12) : null,
                      border: i == 0 ? null : Border(top: BorderSide(color: AppTheme.hairline)),
                    ),
                    child: Row(children: [
                      SizedBox(width: 36, child: Text(b.$1, style: t.titleSmall?.copyWith(color: AppTheme.accounting, fontWeight: FontWeight.w700))),
                      Expanded(
                        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                          Text(b.$2, style: b.$1 == '49' ? t.titleSmall : t.bodyMedium),
                          if (b.$4)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: AppTheme.warningTint, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppTheme.warningBorder)),
                              child: Text('DINA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.warning)),
                            ),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      Text(b.$1 == '49' ? '${_kr(b.$3)} kr' : _kr(b.$3), style: t.titleSmall?.merge(moneyStyle)),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(AppIcons.edit, size: 18),
              label: Text(_manual.isEmpty ? 'Lägg till egna uppgifter (EU-handel m.m.)' : 'Ändra egna uppgifter (${_manual.length} rutor)'),
              onPressed: _editManual,
            ),
            const SizedBox(height: 10),
            _Notice(_manual.isEmpty
                ? 'Beräknat från det som är registrerat i Quee. EU-handel, import och omvänd skattskyldighet ingår inte om du inte lägger till dem själv. Kontrollera siffrorna innan du lämnar in.'
                : 'Det som är markerat DINA har du skrivit in själv. Quee kontrollerar det inte och det finns inte i SIE-filen, så berätta om det för din redovisare. Kontrollera siffrorna innan du lämnar in.'),
            const _Step(1, 'Spara filen på telefonen.'),
            const _Step(2, 'Logga in på Skatteverket, välj Lämna momsdeklaration och Deklarera via fil.'),
            const _Step(3, 'Kontrollera uppgifterna där och skriv under med e-legitimation. Quee skickar inget.'),
            if (_manual.isNotEmpty)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _sure,
                onChanged: (v) => setState(() => _sure = v == true),
                title: const Text('Jag har skrivit in de egna uppgifterna själv och ansvarar för att de stämmer.'),
              ),
            const SizedBox(height: 6),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.accounting),
              icon: const Icon(AppIcons.save, size: 18),
              label: const Text('Spara momsfilen'),
              onPressed: canSend ? () => _save(r) : null,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(AppIcons.mail, size: 18),
              label: const Text('Dela filen'),
              onPressed: canSend ? () => _share(r) : null,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(AppIcons.language, size: 18),
              label: const Text('Öppna Skatteverkets sida'),
              onPressed: () => launchUrl(Uri.parse(_infoUrl), mode: LaunchMode.externalApplication),
            ),
            if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
            const SizedBox(height: 12),
            Text(
                'Filen följer Skatteverkets format för momsdeklaration via fil (eSKDUpload 6.0). Skatteverket kontrollerar den när du laddar upp den, och du kan rätta innan du skriver under. Ruta 49 räknas ut av Quee: utgående moms (10, 11, 12, 30, 31, 32, 60, 61, 62) minus ingående moms (48).',
                style: t.bodySmall),
          ] else
            const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  const _Step(this.n, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppTheme.accounting, shape: BoxShape.circle),
            child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ]),
      );
}

class _Notice extends StatelessWidget {
  final String text;
  final String? button;
  final VoidCallback? onPressed;
  const _Notice(this.text, {this.button, this.onPressed});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.warningTint,
          border: Border.all(color: AppTheme.warningBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(AppIcons.warning, size: 20, color: AppTheme.warning),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: AppTheme.warning, fontSize: 13.5, height: 1.35))),
          ]),
          if (button != null && onPressed != null) ...[
            const SizedBox(height: 10),
            FilledButton(onPressed: onPressed, child: Text(button!)),
          ],
        ]),
      );
}

/// "Egna uppgifter": the boxes of the momsdeklaration Quee cannot work out, for the
/// owner who has the figures. Whole kronor; an empty field means nothing. Returns the
/// typed figures (ruta to kronor) when the owner saves.
class VatManualPage extends StatefulWidget {
  final Map<int, int> initial;
  const VatManualPage({super.key, required this.initial});

  @override
  State<VatManualPage> createState() => _VatManualPageState();
}

class _VatManualPageState extends State<VatManualPage> {
  late final Map<int, TextEditingController> _c = {
    for (final g in vatManualGroups)
      for (final f in g.fields) f.box: TextEditingController(text: widget.initial[f.box]?.toString() ?? ''),
  };
  final Map<int, String> _errors = {};

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final out = <int, int>{};
    _errors.clear();
    for (final e in _c.entries) {
      final s = e.value.text.replaceAll(RegExp(r'[\s ]'), '');
      if (s.isEmpty) continue;
      final v = int.tryParse(s);
      if (v == null) {
        _errors[e.key] = 'Skriv hela kronor, utan decimaler';
      } else if (v != 0) {
        out[e.key] = v;
      }
    }
    if (_errors.isNotEmpty) {
      setState(() {});
      return;
    }
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Egna uppgifter')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _Notice('Skriv bara in det du har siffror för. Hela kronor. Quee räknar ruta 49 åt dig. Är du osäker på vilken ruta något ska i, fråga din redovisare.'),
          for (final g in vatManualGroups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
              child: Text(g.title.toUpperCase(), style: t.labelMedium?.copyWith(color: AppTheme.muted, letterSpacing: 0.4)),
            ),
            for (final f in g.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _c[f.box],
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\s-]'))],
                  decoration: InputDecoration(
                    labelText: 'Ruta ${f.box.toString().padLeft(2, '0')}: ${f.label}',
                    suffixText: 'kr',
                    errorText: _errors[f.box],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 8),
          Text(
              'Säljer du varor till företag i andra EU-länder ska du också lämna en periodisk sammanställning hos Skatteverket. Det gör inte Quee. Det du skriver in här sparas bara på telefonen, per period, och kommer inte med i SIE-filen.',
              style: t.bodySmall),
          const SizedBox(height: 14),
          FilledButton(onPressed: _save, child: const Text('Spara')),
        ],
      ),
    );
  }
}
