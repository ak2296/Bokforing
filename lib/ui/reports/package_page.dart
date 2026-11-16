import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_controller.dart';
import '../../data/accounting_settings.dart';
import '../../domain/report_period.dart';
import '../../export/redovisar_package.dart';
import '../app_icons.dart';
import '../settings/accounting_page.dart';
import '../settings/balances_page.dart';
import '../widgets/blur_overlay.dart';
import 'period_picker.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// "Redovisarpaket": every document the accountant needs for a month, made
/// in one go. Save it as one folder (a ZIP), send the files by e-mail, or pick
/// the papers to print. Says what is missing before anything is made.
class PackagePage extends StatefulWidget {
  /// Where the picker starts when the default is one month.
  final YearMonth? ym;
  const PackagePage({super.key, this.ym});

  @override
  State<PackagePage> createState() => _PackagePageState();
}

class _PackagePageState extends State<PackagePage> {
  ReportPeriod? _period;
  AccountingSettings _acc = const AccountingSettings();
  int _reload = 0;
  bool _busy = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _init();
  }

  Future<void> _init() async {
    final repo = AppScope.read(context).repo;
    final acc = await loadAccounting(repo);
    final start = await repo.fiscalStartMonth();
    final m = widget.ym;
    final base = acc.kind == PeriodKind.month && m != null ? DateTime(m.year, m.month, 1) : DateTime.now();
    if (!mounted) return;
    setState(() {
      _acc = acc;
      _period = ReportPeriod.containing(acc.kind, base, start);
    });
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    final acc = await loadAccounting(AppScope.read(context).repo);
    if (mounted) {
      setState(() {
        _acc = acc;
        _reload++;
      });
    }
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

  Future<void> _saveFolder(PackageData d) => _run(() async {
        final bytes = await zipPackage(d, readme: packageReadme(d));
        final saved = await FilePicker.saveFile(dialogTitle: 'Spara redovisarpaket', fileName: '${d.folderName}.zip', bytes: bytes);
        if (saved != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paketet har sparats som en ZIP-fil med en mapp i.')));
        }
      });

  /// Writes every file of the package to a temporary folder and returns the paths.
  Future<List<String>> _writeFiles(PackageData d) async {
    final dir = Directory(p.join((await getTemporaryDirectory()).path, d.folderName));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final paths = <String>[];
    for (final i in packageContents(d)) {
      for (final (name, bytes) in await itemFiles(d, i)) {
        final f = File(p.join(dir.path, name));
        await f.writeAsBytes(bytes, flush: true);
        paths.add(f.path);
      }
    }
    return paths;
  }

  /// With the accountant's e-mail filled in, the mail app opens with the
  /// recipient, subject, text and every file ready. Without it, the share menu.
  Future<void> _send(PackageData d) => _run(() async {
        final paths = await _writeFiles(d);
        final company = d.profile.name.trim().isEmpty ? 'Quee' : d.profile.name.trim();
        final subject = 'Underlag ${d.period.title}, $company';
        final body = packageMailBody(d, greeting: _acc.greetingName, ownerEmail: _acc.ownerEmail);
        if (!_acc.hasAccountantEmail) {
          await SharePlus.instance.share(ShareParams(files: [for (final f in paths) XFile(f)], subject: subject, text: body));
          return;
        }
        try {
          await FlutterEmailSender.send(Email(
            recipients: [_acc.accountantEmail],
            subject: subject,
            body: body,
            attachmentPaths: paths,
          ));
        } catch (_) {
          // No mail app: the share menu still lists the apps that can send the files.
          await SharePlus.instance.share(ShareParams(files: [for (final f in paths) XFile(f)], subject: subject, text: body));
        }
        if (mounted && _acc.hasAccountantPhone) await _askSms(d);
      });

  /// Back from the mail app: offer a short SMS that says the mail is on its way.
  Future<void> _askSms(PackageData d) async {
    final text = packageSmsText(d, greeting: _acc.greetingName, email: _acc.accountantEmail);
    final digits = _acc.accountantPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    final go = await showBlurSheet<bool>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Skickade du mejlet?', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Skicka ett kort sms${_acc.greetingName.isEmpty ? '' : ' till ${_acc.greetingName}'} så att det syns att underlaget är på väg.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppTheme.hairline, borderRadius: BorderRadius.circular(12)),
            child: Text(text),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text('Öppna sms till ${_acc.accountantPhone}')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Inte nu')),
          const SizedBox(height: 8),
          Text('Sms-appen öppnas med texten färdig. Du trycker själv på skicka. Appen skickar inget sms på egen hand.',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
    if (go == true) {
      await launchUrl(Uri.parse('sms:$digits?body=${Uri.encodeComponent(text)}'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final period = _period;
    return Scaffold(
      appBar: AppBar(title: const Text('Redovisarpaket')),
      body: period == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              PeriodPicker(value: period, onChanged: (v) => setState(() => _period = v)),
              Expanded(
                child: Reloading<PackageData>(
                  deps: '${period.fileTag} ${period.kind.name} $_reload',
                  loader: (c) => loadPackage(c, period),
                  builder: (context, d) {
                    final ready = packageContents(d);
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: LinearGradient(colors: [AppTheme.seed, Color.lerp(AppTheme.seed, Colors.black, 0.28)!]),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Period', style: t.bodySmall?.copyWith(color: Colors.white70)),
                            Text('${d.period.from} – ${d.period.to}',
                                style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('Allt din redovisare behöver, samlat. ${ready.length} dokument ingår.',
                                style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9))),
                          ]),
                        ),
                        if (!d.hasVerifications) ...[
                          const SizedBox(height: 10),
                          _Notice('Det finns inga verifikationer för ${d.period.title}. Skanna Z-rapporter, fakturor och kvitton för perioden. Då fylls rapporterna i.'),
                        ],
                        if (!_acc.hasAccountantEmail) ...[
                          const SizedBox(height: 10),
                          _Notice('Lägg in din redovisares e-post så öppnas mejlet färdigt med mottagare, text och alla filer.',
                              button: 'Fyll i redovisare', onPressed: () => _open(const AccountingPage())),
                        ],
                        const SizedBox(height: 10),
                        Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('DET HÄR INGÅR', style: t.labelMedium?.copyWith(color: AppTheme.muted, letterSpacing: 0.4)),
                              for (final i in d.items) _row(context, i),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          icon: const Icon(AppIcons.save, size: 18),
                          label: const Text('Skapa mapp och spara'),
                          onPressed: _busy || ready.isEmpty ? null : () => _saveFolder(d),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          icon: const Icon(AppIcons.mail, size: 18),
                          label: Text(_acc.hasAccountantEmail
                              ? 'Skicka till ${_acc.accountantName.isEmpty ? _acc.accountantEmail : _acc.accountantName}'
                              : 'Skicka filerna med e-post'),
                          onPressed: _busy || ready.isEmpty ? null : () => _send(d),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          icon: const Icon(AppIcons.print, size: 18),
                          label: const Text('Välj papper att skriva ut'),
                          onPressed: _busy || d.printable.isEmpty ? null : () => _open(PrintPickerPage(data: d)),
                        ),
                        if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
                        const SizedBox(height: 12),
                        Text(
                            'Mappen är en ZIP-fil med en PDF och en Excelfil per rapport, SIE-filen och en läsmig-fil. Mejlet öppnas i din e-postapp och du trycker själv på skicka. Allt bygger på det som är registrerat i Quee. Balansräkningen är ett utkast.',
                            style: t.bodySmall),
                      ],
                    );
                  },
                ),
              ),
            ]),
    );
  }

  Widget _row(BuildContext context, PackageItem i) {
    final t = Theme.of(context).textTheme;
    final ok = i.included && i.problem == null;
    final warn = i.problem != null;
    final color = ok ? AppTheme.seed : AppTheme.warning;
    return InkWell(
      onTap: i.action == 'balances' ? () => _open(const BalancesPage()) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: ok ? AppTheme.seed : Colors.transparent,
              border: ok ? null : Border.all(color: AppTheme.warning, width: 1.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ok ? const Icon(AppIcons.check, size: 14, color: Colors.white) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.title),
              Text(i.detail, style: t.bodySmall?.copyWith(color: warn ? AppTheme.warning : null)),
            ]),
          ),
          Text(ok ? 'klar' : (i.problem ?? ''), style: t.labelMedium?.copyWith(color: color, fontWeight: warn ? FontWeight.w600 : null)),
        ]),
      ),
    );
  }
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

/// "Välj papper att skriva ut": tick the reports to hand over on paper, see the
/// page count, print them together or save them as one PDF.
class PrintPickerPage extends StatefulWidget {
  final PackageData data;
  const PrintPickerPage({super.key, required this.data});

  @override
  State<PrintPickerPage> createState() => _PrintPickerPageState();
}

class _PrintPickerPageState extends State<PrintPickerPage> {
  late final List<PackageItem> _items = widget.data.printable;
  final Map<String, int> _pages = {};
  late final Set<String> _chosen = {
    // Short ones are ticked from the start; the long ledger is left to choose.
    for (final i in _items) if (i.id != 'huvudbok' && i.id != 'saldo') i.id,
  };
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _count();
  }

  Future<void> _count() async {
    for (final i in _items) {
      final n = await i.table!.pageCount(widget.data.profile);
      if (!mounted) return;
      setState(() => _pages[i.id] = n);
    }
  }

  int get _total => [for (final i in _items) if (_chosen.contains(i.id)) _pages[i.id] ?? 0].fold(0, (a, b) => a + b);

  Future<List<int>> _pdf() async => combinedPdf([for (final i in _items) if (_chosen.contains(i.id)) i.table!], widget.data.profile);

  Future<void> _print() async {
    setState(() => _busy = true);
    try {
      await Printing.layoutPdf(name: widget.data.folderName, onLayout: (_) async => Uint8List.fromList(await _pdf()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePdf() async {
    setState(() => _busy = true);
    try {
      final bytes = Uint8List.fromList(await _pdf());
      final saved = await FilePicker.saveFile(dialogTitle: 'Spara utskrifter', fileName: '${widget.data.folderName} utskrifter.pdf', bytes: bytes);
      if (saved != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF-filen har sparats.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Utskrifter')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('Bocka för det du vill lämna som papper. Resten skickar du som filer.', style: t.bodyMedium),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: [
              for (final i in _items)
                CheckboxListTile(
                  value: _chosen.contains(i.id),
                  onChanged: (v) => setState(() => v == true ? _chosen.add(i.id) : _chosen.remove(i.id)),
                  title: Text(i.title),
                  subtitle: i.problem == 'Tom' ? Text(i.detail) : null,
                  secondary: Text(_pages[i.id] == null ? '…' : '${_pages[i.id]} sid', style: t.bodySmall),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
            ]),
          ),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(title: const Text('Valda utskrifter'), trailing: Text('$_total sidor', style: t.titleSmall)),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(AppIcons.print, size: 18),
            label: const Text('Skriv ut valda'),
            onPressed: _busy || _chosen.isEmpty ? null : _print,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(AppIcons.pdf, size: 18),
            label: const Text('Spara som en PDF att skriva ut senare'),
            onPressed: _busy || _chosen.isEmpty ? null : _savePdf,
          ),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        ],
      ),
    );
  }
}
