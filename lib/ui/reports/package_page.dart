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
import '../record_details.dart';
import '../review/invoice_review_page.dart';
import '../settings/accounting_page.dart';
import '../settings/balances_page.dart';
import '../widgets/blur_overlay.dart';
import 'period_picker.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// "Redovisarpaket": every document the accountant needs for a month, made
/// in one go. Save it as one folder (a ZIP), send the files by e-mail, or pick
/// the papers to print. Says what is missing before anything is made.
/// Opens the document or page where a point to look at is fixed.
Future<void> openReviewIssue(BuildContext context, ReviewIssue issue) async {
  switch (issue.target) {
    case IssueTarget.zReport:
      if (issue.id != null) await openRecord(context, 'daily_sales', issue.id!);
    case IssueTarget.invoice:
      if (issue.invoice != null) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => InvoiceReviewPage(existing: issue.invoice)));
      }
    case IssueTarget.balances:
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BalancesPage()));
    case IssueTarget.none:
      break;
  }
}

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

  /// Yellow items the owner confirmed to send as they are; cleared when anything changes.
  final Set<String> _accepted = {};
  bool _busy = false;
  bool _started = false;

  /// The message to the accountant. Written automatically from the package; once the
  /// owner types in it, it is left alone (and kept for the period) until "Skriv om automatiskt".
  final TextEditingController _msg = TextEditingController();
  bool _edited = false;
  PackageData? _data;

  String _msgKey(ReportPeriod p) => 'package_message_${p.fileTag}';

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  /// The text that goes to the accountant: what stands in the field, or the automatic text.
  String _message(PackageData d) =>
      _msg.text.trim().isEmpty ? packageMailBody(d, greeting: _acc.greetingName, ownerEmail: _acc.ownerEmail) : _msg.text;

  /// Keeps the field in step with the package while the owner has not changed it.
  void _syncMessage(PackageData d) {
    _data = d;
    final auto = packageMailBody(d, greeting: _acc.greetingName, ownerEmail: _acc.ownerEmail);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_edited && _msg.text != auto) _msg.text = auto;
    });
  }

  Future<void> _loadMessage(ReportPeriod p) async {
    final saved = await AppScope.read(context).repo.setting(_msgKey(p));
    if (!mounted || _period?.fileTag != p.fileTag) return;
    setState(() {
      _edited = saved != null && saved.isNotEmpty;
      if (_edited) _msg.text = saved!;
    });
  }

  Future<void> _rewriteMessage() async {
    final p = _period;
    if (p != null) await AppScope.read(context).repo.setSetting(_msgKey(p), '');
    if (!mounted) return;
    setState(() => _edited = false);
    final d = _data;
    if (d != null) _syncMessage(d);
  }

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
    final period = ReportPeriod.containing(acc.kind, base, start);
    setState(() {
      _acc = acc;
      _period = period;
    });
    await _loadMessage(period);
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    final acc = await loadAccounting(AppScope.read(context).repo);
    if (mounted) {
      setState(() {
        _acc = acc;
        _accepted.clear();
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
        final bytes = await zipPackage(d, readme: packageReadme(d, message: _message(d)));
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
        final body = _message(d);
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
              PeriodPicker(value: period, onChanged: (v) {
                setState(() {
                  _accepted.clear();
                  _period = v;
                  _edited = false;
                  _msg.clear();
                });
                _loadMessage(v);
              }),
              Expanded(
                child: Reloading<PackageData>(
                  deps: '${period.fileTag} ${period.kind.name} $_reload',
                  loader: (c) => loadPackage(c, period),
                  builder: (context, d) {
                    d.accepted
                      ..clear()
                      ..addAll(_accepted);
                    final ready = packageContents(d);
                    _syncMessage(d);
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
                        if (d.status != PackageStatus.empty) ...[
                          const SizedBox(height: 10),
                          _statusLine(context, d),
                        ],
                        const SizedBox(height: 10),
                        Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('DET HÄR INGÅR', style: t.labelMedium?.copyWith(color: AppTheme.muted, letterSpacing: 0.4)),
                              for (final i in d.allItems) _row(context, d, i),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text('MEDDELANDE TILL REDOVISAREN', style: t.labelMedium?.copyWith(color: AppTheme.muted, letterSpacing: 0.4)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _msg,
                          minLines: 8,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (v) {
                            if (!_edited) setState(() => _edited = true);
                            final p = _period;
                            if (p != null) AppScope.read(context).repo.setSetting(_msgKey(p), v);
                          },
                        ),
                        Row(children: [
                          Expanded(child: Text(_edited ? 'Du har ändrat texten.' : 'Skrivs automatiskt. Ändra fritt.', style: t.bodySmall)),
                          if (_edited) TextButton(onPressed: _rewriteMessage, child: const Text('Skriv om automatiskt')),
                        ]),
                        const SizedBox(height: 10),
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

  /// One line under the header: where the package stands. Open points open the list.
  Widget _statusLine(BuildContext context, PackageData d) {
    final t = Theme.of(context).textTheme;
    final open = d.status == PackageStatus.open;
    final color = open ? AppTheme.warning : AppTheme.seed;
    final text = switch (d.status) {
      PackageStatus.accepted => 'Klart, med ${d.issues.length} ${d.issues.length == 1 ? 'punkt' : 'punkter'} du har godkänt',
      PackageStatus.open => packageStatusText(d),
      _ => 'Klart att skicka',
    };
    final sub = switch (d.status) {
      PackageStatus.accepted => 'Din redovisare ser dem i "Att känna till"',
      PackageStatus.open => 'Tryck för att öppna listan och rätta eller godkänna',
      _ => null,
    };
    return Material(
      color: open ? AppTheme.warningTint : AppTheme.tint,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: open ? AppTheme.warningBorder : AppTheme.hairline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: d.status == PackageStatus.ready ? null : () => _review(d),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(open ? AppIcons.warning : AppIcons.check, size: 14, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(text, style: t.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
                if (sub != null) Text(sub, style: t.bodySmall?.copyWith(color: color)),
              ]),
            ),
            if (d.status != PackageStatus.ready) Icon(AppIcons.chevronRight, size: 18, color: color),
          ]),
        ),
      ),
    );
  }

  /// The list of everything yellow. A tap on a line opens the place where it is fixed.
  /// At the bottom the owner confirms to send as it is; only then the row is ticked.
  Future<void> _review(PackageData d) async {
    final result = await showBlurSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ReviewSheet(d),
    );
    if (!mounted) return;
    if (result is ReviewIssue) {
      await openReviewIssue(context, result);
      // Fixed things turn normal again; what is still yellow needs a new confirmation.
      if (mounted) {
        setState(() {
          _accepted.clear();
          _reload++;
        });
      }
    } else if (result == true) {
      setState(() => _accepted
        ..clear()
        ..addAll([for (final i in d.items) if (PackageData.needsOk(i) && i.included) i.id]));
    } else if (result == false) {
      setState(_accepted.clear);
    }
  }

  Widget _row(BuildContext context, PackageData d, PackageItem i) {
    final t = Theme.of(context).textTheme;
    final yellow = PackageData.needsOk(i);
    final accepted = yellow && _accepted.contains(i.id);
    final ok = i.included && !yellow;
    final color = ok ? AppTheme.seed : AppTheme.warning;
    final label = ok ? 'klar' : accepted ? 'godkänd av dig' : (i.problem ?? '');
    return InkWell(
      onTap: yellow ? () => _review(d) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: ok ? AppTheme.seed : accepted ? AppTheme.warning : Colors.transparent,
              border: ok ? null : Border.all(color: AppTheme.warning, width: 1.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ok || accepted ? const Icon(AppIcons.check, size: 14, color: Colors.white) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.title),
              Text(i.detail, style: t.bodySmall?.copyWith(color: yellow ? AppTheme.warning : null)),
            ]),
          ),
          Text(label, style: t.labelMedium?.copyWith(color: color, fontWeight: yellow ? FontWeight.w600 : null)),
        ]),
      ),
    );
  }
}

/// "Att se över": every yellow point, each opening where it is fixed, and the owner's
/// own confirmation to send the package although some of it is not as it should be.
class _ReviewSheet extends StatefulWidget {
  final PackageData data;
  const _ReviewSheet(this.data);

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  bool _sure = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = widget.data;
    final already = d.accepted.isNotEmpty;
    final canAccept = d.items.any((i) => PackageData.needsOk(i) && i.included);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Att se över före du skickar', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Tryck på en rad för att öppna dokumentet och rätta det. Det som inte går att rätta kan du godkänna längst ned.', style: t.bodyMedium),
          const SizedBox(height: 12),
          if (d.issues.isEmpty)
            Text('Inget att se över.', style: t.bodyMedium)
          else
            for (final i in d.issues)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: AppTheme.warningTint,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.warningBorder)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: i.target == IssueTarget.none ? null : () => Navigator.pop(context, i),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Expanded(child: Text(i.text, style: TextStyle(color: AppTheme.warning, fontSize: 14))),
                        if (i.target != IssueTarget.none) Icon(AppIcons.chevronRight, size: 18, color: AppTheme.warning),
                      ]),
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 8),
          if (canAccept && !already) ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _sure,
              onChanged: (v) => setState(() => _sure = v == true),
              title: const Text('Jag har tagit del av punkterna ovan och godkänner att underlaget skickas som det är. Jag ansvarar för att uppgifterna stämmer.'),
            ),
            FilledButton(onPressed: _sure ? () => Navigator.pop(context, true) : null, child: const Text('Godkänn och ta med')),
          ],
          if (already) OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ta bort mitt godkännande')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Stäng')),
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
