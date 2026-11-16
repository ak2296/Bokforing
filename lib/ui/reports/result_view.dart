import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_controller.dart';
import '../../domain/cost_types.dart';
import '../../domain/models.dart';
import '../../data/balances_store.dart';
import '../../domain/balances.dart';
import '../../data/accounting_settings.dart';
import '../../domain/ledger.dart';
import '../../domain/report_period.dart';
import '../settings/balances_page.dart';
import 'period_picker.dart';
import 'report_hero.dart';
import '../../domain/money.dart';
import '../../domain/result_report.dart';
import '../../export/sie_export.dart';
import '../../export/table_export.dart';
import '../app_icons.dart';
import '../export_actions.dart';
import '../incomplete_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/result_charts.dart';
import 'sie_preview_page.dart';
import '../widgets/blur_overlay.dart';

/// The period of a resultatrapport: one month or one financial year.
class _Period {
  final String title;
  final String from;
  final String to;
  final String yearFrom;
  final String yearTo;
  final String fileTag;
  const _Period(this.title, this.from, this.to, this.yearFrom, this.yearTo, this.fileTag);

  factory _Period.of(ReportPeriod p) => _Period(p.title, p.from, p.to, p.yearFrom, p.yearTo, p.fileTag);
}

/// "Resultat": a simple resultatrapport and the SIE file for the accountant.
class ResultView extends StatefulWidget {
  const ResultView({super.key});

  @override
  State<ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<ResultView> {
  ReportPeriod? _period;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_period == null) _init();
  }

  Future<void> _init() async {
    final repo = AppScope.read(context).repo;
    final acc = await loadAccounting(repo);
    final start = await repo.fiscalStartMonth();
    if (mounted) setState(() => _period = ReportPeriod.containing(acc.kind, DateTime.now(), start));
  }

  @override
  Widget build(BuildContext context) {
    final period = _period;
    if (period == null) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        PeriodPicker(value: period, onChanged: (v) => setState(() => _period = v)),
        Expanded(
          child: Reloading<_Data>(
            deps: '${period.kind.name} ${period.fileTag}',
            loader: (c) => _Data.load(c, period),
            builder: (context, data) => _ResultBody(data: data),
          ),
        ),
      ],
    );
  }
}

class _Data {
  final _Period period;
  final ResultReport report;
  final BusinessProfile profile;
  final List<DailySales> sales;
  final List<Invoice> invoices;
  final List<OnlineSale> online;
  final List<Payslip> payslips;
  final OpeningBalances balances;
  const _Data(this.period, this.report, this.profile, this.sales, this.invoices, this.online, this.payslips, this.balances);

  /// The balance sheet on the last day of the period: the opening balances plus
  /// every verification from the balance date. Null when there is no opening balance
  /// or it is dated after the period.
  Future<BalanceSheet?> balanceSheet(AppController c) async {
    if (balances.isEmpty || balances.date.compareTo(period.to) > 0) return null;
    final from = balances.date;
    final ledger = Ledger.of(SieExport.vouchers(
      fromIso: from,
      toIso: period.to,
      sales: await c.repo.dailySalesBetween(from, period.to),
      invoices: await c.repo.invoicesBetween('2000-01-01', period.to),
      online: await c.repo.onlineSalesBetween(from, period.to),
      payslips: await c.repo.payslipsBetween(from, period.to),
    ));
    return BalanceSheet.build(balances, ledger, period.to);
  }

  static Future<_Data> load(AppController c, ReportPeriod rp) async {
    final p = _Period.of(rp);
    final sales = await c.repo.dailySalesBetween(p.from, p.to);
    final invoices = await c.repo.invoicesForReports(p.from, p.to);
    final online = await c.repo.onlineSalesBetween(p.from, p.to);
    // Payments made in the period for invoices from before it belong in the SIE file.
    final upToEnd = await c.repo.invoicesBetween('2000-01-01', p.to);
    final report = ResultReport.build(
        title: p.title, fromIso: p.from, toIso: p.to, sales: sales, invoices: invoices, online: online);
    final payslips = await c.repo.payslipsBetween(p.from, p.to);
    return _Data(p, report, await c.repo.profile(), sales, upToEnd, online, payslips, await loadBalances(c.repo));
  }

  /// The verifications of the period, as the SIE file gets them.
  Ledger ledger() => Ledger.of(SieExport.vouchers(
        fromIso: period.from,
        toIso: period.to,
        sales: sales,
        invoices: invoices,
        online: online,
        payslips: payslips,
      ));

  ReportTable table() {
    final r = report;
    String m(Money v) => v.format(unit: false);
    return ReportTable(
      title: 'Resultatrapport ${period.title}',
      fileName: 'resultatrapport_${period.fileTag}',
      headers: const ['Post', 'Belopp (kr)', 'Antal fakturor'],
      rows: [
        ['Försäljning i kassan exkl. moms', m(r.cashSales), ''],
        ['Onlineförsäljning exkl. moms', m(r.onlineSales), ''],
        ['Summa intäkter', m(r.sales), ''],
        for (final c in r.costs) [c.label, m(-c.net), '${c.count}'],
        ['Summa kostnader', m(-r.totalCosts), ''],
      ],
      totals: ['Resultat', m(r.result), ''],
    );
  }
}

class _ResultBody extends StatelessWidget {
  final _Data data;
  const _ResultBody({required this.data});

  Future<void> _exportSie(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final p = data.period;
    try {
      final text = SieExport.build(
        profile: data.profile,
        fromIso: p.from,
        toIso: p.to,
        yearStartIso: p.yearFrom,
        yearEndIso: p.yearTo,
        sales: data.sales,
        invoices: data.invoices,
        online: data.online,
        payslips: data.payslips,
      );
      final bytes = SieExport.encode(text);
      final fileName = 'quee_${p.fileTag}.se';
      if (!context.mounted) return;
      final email = await showBlurSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (c) => Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(AppIcons.mail),
            title: const Text('Skicka med e-post'),
            subtitle: const Text('Öppnar e-posten med filen bifogad'),
            onTap: () => Navigator.pop(c, true),
          ),
          ListTile(
            leading: const Icon(AppIcons.save),
            title: const Text('Spara på telefonen'),
            onTap: () => Navigator.pop(c, false),
          ),
          const SizedBox(height: 8),
        ]),
      );
      if (email == null) return;
      if (email) {
        // The share menu lists the mail apps; the recipient is chosen there.
        final company = data.profile.name.trim().isEmpty ? 'Quee' : data.profile.name.trim();
        final file = File(path.join((await getTemporaryDirectory()).path, fileName));
        await file.writeAsBytes(bytes, flush: true);
        await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path, mimeType: 'application/octet-stream')],
          subject: 'SIE-fil $company, ${p.title}',
          text: 'Hej!\n\nHär kommer SIE-filen för ${p.title} från $company '
              '(${p.from} – ${p.to}). Den kan läsas in i Fortnox, Visma, Bokio och andra bokföringsprogram.\n\nVänliga hälsningar\n$company',
        ));
        return;
      }
      final uri = await FilePicker.saveFile(dialogTitle: 'Spara SIE-fil', fileName: fileName, bytes: bytes);
      if (uri == null) return;
      messenger.showSnackBar(const SnackBar(content: Text('SIE-filen har sparats. Skicka den till din redovisare.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('SIE-filen kunde inte skapas: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = data.report;
    final t = Theme.of(context).textTheme;
    final bold = moneyStyle.copyWith(fontWeight: FontWeight.bold);
    final p = data.period;
    // data.invoices reaches back before the period (for the SIE file); count this period only.
    final incomplete = data.invoices
        .where((i) => i.bookingDate.compareTo(p.from) >= 0 && i.bookingDate.compareTo(p.to) <= 0 && i.isIncomplete)
        .length;
    Widget row(String label, Money v, {bool strong = false, String? sub}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: strong ? t.titleSmall : t.bodyMedium),
                if (sub != null) Text(sub, style: t.bodySmall),
              ]),
            ),
            Text(v.format(), style: strong ? bold : moneyStyle),
          ]),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
      children: [
        ReportHero(
          color: AppTheme.pumpkin,
          label: 'Resultat ${p.title}',
          value: r.result.format(),
          chips: [
            ('Intäkter', r.sales.format(compact: true)),
            ('Kostnader', r.totalCosts.format(compact: true)),
          ],
        ),
        const SizedBox(height: 12),
        if (incomplete > 0) ...[
          IncompleteNotice(count: incomplete, from: p.from, to: p.to, period: p.title),
          const SizedBox(height: 12),
        ],
        ExportButtons(
          onPdf: () => exportTablePdf(context, data.table(), data.profile),
          onExcel: () => exportTableCsv(context, data.table()),
          onPrint: () => printTable(context, data.table(), data.profile),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(AppIcons.file, size: 18),
          label: const Text('SIE-fil till redovisaren'),
          onPressed: () => _exportSie(context),
        ),
        const SizedBox(height: 16),
        Text('Bokföringsrapporter', style: t.titleMedium),
        Text('Byggda på samma verifikationer som SIE-filen: bara det som finns registrerat i appen, utan ingående balanser.',
            style: t.bodySmall),
        const SizedBox(height: 8),
        if (data.ledger().vouchers.isEmpty)
          const _NeedsCard(
            icon: AppIcons.scan,
            text: 'Det finns inga verifikationer för perioden. Skanna Z-rapporter, fakturor och kvitton för perioden, så fylls rapporterna i.',
          ),
        for (final (label, build) in data.ledger().vouchers.isEmpty
            ? const <(String, ReportTable Function(Ledger, String))>[]
            : <(String, ReportTable Function(Ledger, String))>[
          ('Momsunderlag', vatBasisTable),
          ('Verifikationslista', voucherListTable),
          ('Huvudbok', generalLedgerTable),
          ('Saldobalans', trialBalanceTable),
          ('Resultaträkning (BAS)', incomeStatementTable),
        ]) ...[
          Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Text(label, style: t.labelLarge)),
          ExportButtons(
            onPdf: () => exportTablePdf(context, build(data.ledger(), p.title), data.profile),
            onExcel: () => exportTableCsv(context, build(data.ledger(), p.title)),
            onPrint: () => printTable(context, build(data.ledger(), p.title), data.profile),
          ),
        ],
        const SizedBox(height: 16),
        Text('Balansräkning', style: t.titleMedium),
        if (data.balances.isEmpty || data.balances.date.compareTo(p.to) > 0)
          _NeedsCard(
            icon: AppIcons.report,
            text: data.balances.isEmpty
                ? 'Balansräkningen behöver dina ingående balanser: bank, tillgångar och lån den första dagen på räkenskapsåret.'
                : 'Dina ingående balanser gäller från ${data.balances.date}, efter den här perioden. Välj en period från det datumet.',
            button: 'Fyll i ingående balanser',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BalancesPage())),
          )
        else ...[
          Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Text('Balansräkning (utkast)', style: t.labelLarge)),
          ExportButtons(
            onPdf: () async {
              final s = await data.balanceSheet(AppScope.read(context));
              if (s != null && context.mounted) await exportTablePdf(context, balanceSheetTable(s), data.profile);
            },
            onExcel: () async {
              final s = await data.balanceSheet(AppScope.read(context));
              if (s != null && context.mounted) await exportTableCsv(context, balanceSheetTable(s));
            },
            onPrint: () async {
              final s = await data.balanceSheet(AppScope.read(context));
              if (s != null && context.mounted) await printTable(context, balanceSheetTable(s), data.profile);
            },
          ),
          if (data.balances.entries.any((e) => depreciationPlan(e, 2000).isNotEmpty)) ...[
            Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Text('Avskrivningsplan', style: t.labelLarge)),
            ExportButtons(
              onPdf: () => exportTablePdf(context, depreciationTable(data.balances), data.profile),
              onExcel: () => exportTableCsv(context, depreciationTable(data.balances)),
              onPrint: () => printTable(context, depreciationTable(data.balances), data.profile),
            ),
          ],
          if (data.balances.entries.any((e) => loanFirstMonth(e) != null)) ...[
            Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Text('Lånplan', style: t.labelLarge)),
            ExportButtons(
              onPdf: () => exportTablePdf(context, loanTable(data.balances), data.profile),
              onExcel: () => exportTableCsv(context, loanTable(data.balances)),
              onPrint: () => printTable(context, loanTable(data.balances), data.profile),
            ),
          ],
          Text('Utkast, baserat på uppgifter du lagt in. Inte en officiell balansräkning.', style: t.bodySmall),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(AppIcons.search, size: 18),
          label: const Text('Förhandsvisa SIE'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SiePreviewPage(
              period: data.period.title,
              vouchers: SieExport.vouchers(
                fromIso: data.period.from,
                toIso: data.period.to,
                sales: data.sales,
                invoices: data.invoices,
                online: data.online,
                payslips: data.payslips,
              ),
            ),
          )),
        ),
        if (r.sales.ore > 0 || r.costs.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Från intäkter till resultat', style: t.titleMedium),
                const SizedBox(height: 8),
                ResultWaterfall(r),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Intäkter', style: t.titleMedium),
              row('Försäljning i kassan', r.cashSales, sub: 'Z-rapporter, exkl. moms'),
              row('Onlineförsäljning', r.onlineSales, sub: 'Exkl. moms'),
              row('Summa intäkter', r.sales, strong: true),
              const Divider(),
              Text('Kostnader', style: t.titleMedium),
              if (r.costs.isEmpty) const Text('Inga fakturor eller kvitton under perioden.'),
              for (final c in r.costs)
                row(c.label, -c.net, sub: _countText(c)),
              row('Summa kostnader', -r.totalCosts, strong: true),
              const Divider(),
              row('Resultat', r.result, strong: true),
            ]),
          ),
        ),
        if (r.sales.ore > 0 || r.costs.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Kostnader i procent av försäljningen', style: t.titleMedium),
                const SizedBox(height: 8),
                CostShare(r),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Bygger bara på det som är registrerat i appen. Den officiella resultaträkningen görs i bokföringen, '
          't.ex. av din redovisare från SIE-filen.',
          style: t.bodySmall,
        ),
      ],
    );
  }
}

/// "3 fakturor, exkl. moms", or "1 lönebesked, utan moms" for Löner and
/// Sociala avgifter, which come from lönebesked.
String _countText(ResultCost c) => c.costType == CostType.salaries.key || c.costType == CostType.socialFees.key
    ? '${c.count} lönebesked, utan moms'
    : '${c.count} ${c.count == 1 ? 'faktura' : 'fakturor'}, exkl. moms';

/// A report that needs something from the owner: says what, and where to fill it in.
class _NeedsCard extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? button;
  final VoidCallback? onPressed;
  const _NeedsCard({required this.icon, required this.text, this.button, this.onPressed});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.warningTint,
          border: Border.all(color: AppTheme.warningBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: AppTheme.warning),
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
