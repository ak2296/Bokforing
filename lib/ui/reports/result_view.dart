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
import '../../domain/ledger.dart';
import '../../domain/report_period.dart';
import '../settings/balances_page.dart';
import 'period_picker.dart';
import 'report_hero.dart';
import '../../domain/dates.dart';
import '../../domain/money.dart';
import '../../domain/result_report.dart';
import '../../export/sie_export.dart';
import '../../export/table_export.dart';
import '../app_icons.dart';
import '../export_actions.dart';
import '../incomplete_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ledger_parts.dart';
import '../widgets/result_charts.dart';
import 'package_page.dart';
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

/// Which part of the period's figures a [ResultView] shows.
enum ResultMode { resultat, balans, redovisning }

/// The body of Bokslut (Resultat and Balans) and of Redovisning. The period is
/// chosen on the reports page, so the three views always show the same one.
class ResultView extends StatelessWidget {
  final ReportPeriod period;
  final ValueChanged<ReportPeriod> onChanged;
  final ResultMode mode;
  final YearMonth ym;
  const ResultView({super.key, required this.period, required this.onChanged, required this.mode, required this.ym});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          PeriodPicker(value: period, onChanged: onChanged),
          Expanded(
            child: Reloading<_Data>(
              deps: '${period.kind.name} ${period.fileTag}',
              loader: (c) => _Data.load(c, period),
              builder: (context, data) => switch (mode) {
                ResultMode.resultat => _ResultBody(data: data),
                ResultMode.balans => _BalanceBody(data: data),
                ResultMode.redovisning => _AccountingBody(data: data, ym: ym),
              },
            ),
          ),
        ],
      );
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

  /// The company form decides the account for what the owner paid privately.
  final CompanyForm? form;
  const _Data(this.period, this.report, this.profile, this.sales, this.invoices, this.online, this.payslips, this.balances,
      {this.form});

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
      form: form,
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
    return _Data(p, report, await c.repo.profile(), sales, upToEnd, online, payslips, await loadBalances(c.repo),
        form: await c.repo.companyForm());
  }

  /// The verifications of the period, as the SIE file gets them.
  Ledger ledger() => Ledger.of(SieExport.vouchers(
        fromIso: period.from,
        toIso: period.to,
        sales: sales,
        invoices: invoices,
        online: online,
        payslips: payslips,
        form: form,
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

Future<void> _exportSie(BuildContext context, _Data data) async {
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
      form: data.form,
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

class _ResultBody extends StatelessWidget {
  final _Data data;
  const _ResultBody({required this.data});

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

/// A numbered heading with a short explanation under it: the steps of Redovisning.
class _Step extends StatelessWidget {
  final int number;
  final String title;
  final String? text;
  const _Step(this.number, this.title, {this.text});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppTheme.accounting, shape: BoxShape.circle),
            child: Text('$number', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: t.titleMedium)),
        ]),
        if (text != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(text!, style: t.bodySmall)),
      ]),
    );
  }
}

/// A row that opens something: icon, title, optional line under it, arrow.
class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _ActionRow({required this.icon, required this.title, this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: AppTheme.accounting.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, size: 18, color: AppTheme.accounting),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                if (subtitle != null) Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            Icon(AppIcons.chevronRight, size: 18, color: AppTheme.accounting),
          ]),
        ),
      );
}

/// A report with its three ways out on one line: PDF, Excel and print.
class _ExportRow extends StatelessWidget {
  final String label;
  final VoidCallback onPdf;
  final VoidCallback onExcel;
  final VoidCallback onPrint;
  const _ExportRow({required this.label, required this.onPdf, required this.onExcel, required this.onPrint});

  @override
  Widget build(BuildContext context) {
    Widget chip(String text, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10), side: BorderSide(color: AppTheme.accounting.withValues(alpha: 0.45))),
            child: InkWell(
              customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onTap: onTap,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                alignment: Alignment.center,
                child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.accounting)),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(children: [
        Expanded(child: Text(label, style: Theme.of(context).textTheme.titleSmall)),
        chip('PDF', onPdf),
        chip('Excel', onExcel),
        chip('Skriv ut', onPrint),
      ]),
    );
  }
}

/// "Balans": the balance sheet draft on the last day of the period, from the
/// opening balances and everything registered since.
class _BalanceBody extends StatelessWidget {
  final _Data data;
  const _BalanceBody({required this.data});

  @override
  Widget build(BuildContext context) {
    final p = data.period;
    if (data.balances.isEmpty || data.balances.date.compareTo(p.to) > 0) {
      return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 112), children: [
        _NeedsCard(
          icon: AppIcons.report,
          text: data.balances.isEmpty
              ? 'Balansen behöver dina ingående balanser: bank, tillgångar och lån den första dagen på räkenskapsåret.'
              : 'Dina ingående balanser gäller från ${data.balances.date}, efter den här perioden. Välj en period från det datumet.',
          button: 'Fyll i ingående balanser',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BalancesPage())),
        ),
      ]);
    }
    return Reloading<BalanceSheet?>(
      deps: '${p.fileTag} ${data.balances.date} ${data.balances.entries.length}',
      loader: (c) => data.balanceSheet(c),
      builder: (context, s) => s == null ? const SizedBox.shrink() : _balanceList(context, s),
    );
  }

  Widget _balanceList(BuildContext context, BalanceSheet s) {
    final t = Theme.of(context).textTheme;
    final equity = s.equityDebtRows
        .firstWhere((r) => r.label == 'Summa eget kapital', orElse: () => const BalanceRow('', Money.zero))
        .amount;
    final debts = s.totalEquityDebts - equity;
    Widget line(BalanceRow r) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(child: Text(r.label, style: r.strong ? t.titleSmall : t.bodyMedium)),
            Text(r.amount.format(), style: r.strong ? moneyStyle.copyWith(fontWeight: FontWeight.w600) : moneyStyle),
          ]),
        );
    Widget total(String label, Money m) => Column(children: [
          const Divider(),
          Row(children: [
            Expanded(child: Text(label, style: t.titleSmall)),
            Text(m.format(), style: moneyStyle.copyWith(fontWeight: FontWeight.w600)),
          ]),
        ]);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
      children: [
        ReportHero(
          color: AppTheme.balance,
          label: 'Balans ${SwedishDates.mediumDay(s.asOf)} (utkast)',
          value: s.totalAssets.format(),
          chips: [('Eget kapital', equity.format(compact: true)), ('Skulder', debts.format(compact: true))],
        ),
        const SizedBox(height: 12),
        if (equity.ore > 0 && debts.ore > 0) ...[
          ShareBar(parts: [('Eget kapital', equity), ('Skulder', debts)], colors: const [Color(0xFF4B8F7A), Color(0xFFC9A24A)]),
          const SizedBox(height: 8),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text('Tillgångar', style: t.titleMedium)),
                s.balances
                    ? StatusChip('Balanserar', color: AppTheme.seed, background: AppTheme.tint)
                    : const StatusChip('Balanserar inte'),
              ]),
              const SizedBox(height: 4),
              if (s.assetRows.isEmpty) Text('Inga tillgångar är ifyllda.', style: t.bodySmall),
              for (final r in s.assetRows) line(r),
              total('Summa tillgångar', s.totalAssets),
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Eget kapital och skulder', style: t.titleMedium),
              const SizedBox(height: 4),
              for (final r in s.equityDebtRows) line(r),
              total('Summa eget kapital och skulder', s.totalEquityDebts),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        Text(
            'Utkast, baserat på dina ingående balanser och det som är registrerat i appen. Inte en officiell balansräkning. '
            'PDF, Excel och utskrift finns under Redovisning.',
            style: t.bodySmall),
      ],
    );
  }
}

/// "Redovisning": everything for the accountant in one place, in the order it is
/// used: the package, the SIE file, the bookkeeping reports and the balance papers.
class _AccountingBody extends StatelessWidget {
  final _Data data;
  final YearMonth ym;
  const _AccountingBody({required this.data, required this.ym});

  @override
  Widget build(BuildContext context) {
    final p = data.period;
    final t = Theme.of(context).textTheme;
    final ledger = data.ledger();
    final noVouchers = ledger.vouchers.isEmpty;
    final incomplete = data.invoices
        .where((i) => i.bookingDate.compareTo(p.from) >= 0 && i.bookingDate.compareTo(p.to) <= 0 && i.isIncomplete)
        .length;
    final balanceOk = !(data.balances.isEmpty || data.balances.date.compareTo(p.to) > 0);
    Future<void> sheet(Future<void> Function(BalanceSheet s) go) async {
      final s = await data.balanceSheet(AppScope.read(context));
      if (s != null && context.mounted) await go(s);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
      children: [
        ReportHero(
          color: AppTheme.accounting,
          label: 'Redovisning ${p.title}',
          value: noVouchers ? 'Inget att skicka än' : (incomplete > 0 ? 'Kontrollera först' : 'Redo att skicka'),
          chips: [('Verifikationer', '${ledger.vouchers.length}'), ('Saknar uppgift', '$incomplete')],
        ),
        const SizedBox(height: 12),
        if (incomplete > 0) ...[
          IncompleteNotice(count: incomplete, from: p.from, to: p.to, period: p.title),
          const SizedBox(height: 12),
        ],
        Material(
          color: AppTheme.accounting,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PackagePage(ym: ym))),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Icon(AppIcons.report, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Redovisarpaket', style: t.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                    Text('Rapporter och SIE-fil i en mapp, e-post eller sms',
                        style: t.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.9))),
                  ]),
                ),
                const Icon(AppIcons.chevronRight, color: Colors.white),
              ]),
            ),
          ),
        ),
        const _Step(1, 'SIE-fil', text: 'Till Fortnox, Visma, Bokio och andra bokföringsprogram.'),
        LedgerCard(children: [
          _ActionRow(icon: AppIcons.file, title: 'SIE-fil till redovisaren', onTap: () => _exportSie(context, data)),
          _ActionRow(
            icon: AppIcons.search,
            title: 'Förhandsvisa SIE',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SiePreviewPage(
                period: p.title,
                vouchers: SieExport.vouchers(
                  fromIso: p.from,
                  toIso: p.to,
                  sales: data.sales,
                  invoices: data.invoices,
                  online: data.online,
                  payslips: data.payslips,
                  form: data.form,
                ),
              ),
            )),
          ),
        ]),
        const _Step(2, 'Bokföringsrapporter',
            text: 'Byggda på samma verifikationer som SIE-filen: bara det som finns registrerat i appen, utan ingående balanser.'),
        if (noVouchers)
          const _NeedsCard(
            icon: AppIcons.scan,
            text: 'Det finns inga verifikationer för perioden. Skanna Z-rapporter, fakturor och kvitton för perioden, så fylls rapporterna i.',
          )
        else
          LedgerCard(children: [
            for (final (label, build) in <(String, ReportTable Function(Ledger, String))>[
              ('Momsunderlag', vatBasisTable),
              ('Verifikationslista', voucherListTable),
              ('Huvudbok', generalLedgerTable),
              ('Saldobalans', trialBalanceTable),
              ('Resultaträkning (BAS)', incomeStatementTable),
            ])
              _ExportRow(
                label: label,
                onPdf: () => exportTablePdf(context, build(ledger, p.title), data.profile),
                onExcel: () => exportTableCsv(context, build(ledger, p.title)),
                onPrint: () => printTable(context, build(ledger, p.title), data.profile),
              ),
          ]),
        const _Step(3, 'Balansunderlag', text: 'Balansen visas under Bokslut. Här sparar och skriver du ut den.'),
        if (!balanceOk)
          _NeedsCard(
            icon: AppIcons.report,
            text: data.balances.isEmpty
                ? 'Balansräkningen behöver dina ingående balanser: bank, tillgångar och lån den första dagen på räkenskapsåret.'
                : 'Dina ingående balanser gäller från ${data.balances.date}, efter den här perioden. Välj en period från det datumet.',
          )
        else
          LedgerCard(children: [
            _ExportRow(
              label: 'Balansräkning (utkast)',
              onPdf: () => sheet((s) => exportTablePdf(context, balanceSheetTable(s), data.profile)),
              onExcel: () => sheet((s) => exportTableCsv(context, balanceSheetTable(s))),
              onPrint: () => sheet((s) => printTable(context, balanceSheetTable(s), data.profile)),
            ),
            if (data.balances.entries.any((e) => depreciationPlan(e, 2000).isNotEmpty))
              _ExportRow(
                label: 'Avskrivningsplan',
                onPdf: () => exportTablePdf(context, depreciationTable(data.balances), data.profile),
                onExcel: () => exportTableCsv(context, depreciationTable(data.balances)),
                onPrint: () => printTable(context, depreciationTable(data.balances), data.profile),
              ),
            if (data.balances.entries.any((e) => loanFirstMonth(e) != null))
              _ExportRow(
                label: 'Lånplan',
                onPdf: () => exportTablePdf(context, loanTable(data.balances), data.profile),
                onExcel: () => exportTableCsv(context, loanTable(data.balances)),
                onPrint: () => printTable(context, loanTable(data.balances), data.profile),
              ),
          ]),
        const SizedBox(height: 8),
        LedgerCard(children: [
          _ActionRow(
            icon: AppIcons.edit,
            title: 'Ingående balanser',
            subtitle: 'Bank, tillgångar och lån',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BalancesPage())),
          ),
        ]),
        const SizedBox(height: 8),
        Text('Utkast, baserat på uppgifter du lagt in. Inte en officiell balansräkning.', style: t.bodySmall),
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
