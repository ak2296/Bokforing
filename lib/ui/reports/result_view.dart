import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_controller.dart';
import '../../domain/cost_types.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
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

/// The period of a resultatrapport: one month or one financial year.
class _Period {
  final String title;
  final String from;
  final String to;
  final String yearFrom;
  final String yearTo;
  final String fileTag;
  const _Period(this.title, this.from, this.to, this.yearFrom, this.yearTo, this.fileTag);

  /// The financial year that starts in [startMonth] of [year].
  static (String, String) financialYear(int year, int startMonth) {
    final start = DateTime(year, startMonth, 1);
    final end = DateTime(year + 1, startMonth, 1).subtract(const Duration(days: 1));
    return (SwedishDates.iso(start), SwedishDates.iso(end));
  }

  factory _Period.month(YearMonth ym, int startMonth) {
    final from = DateTime(ym.year, ym.month, 1);
    final to = DateTime(ym.year, ym.month + 1, 1).subtract(const Duration(days: 1));
    final fyStartYear = ym.month >= startMonth ? ym.year : ym.year - 1;
    final (yf, yt) = financialYear(fyStartYear, startMonth);
    return _Period(ym.title, SwedishDates.iso(from), SwedishDates.iso(to), yf, yt,
        '${ym.year}-${ym.month.toString().padLeft(2, '0')}');
  }

  factory _Period.year(int year, int startMonth) {
    final (yf, yt) = financialYear(year, startMonth);
    final title = startMonth == 1 ? 'Året $year' : 'Räkenskapsåret $yf – $yt';
    return _Period(title, yf, yt, yf, yt, startMonth == 1 ? '$year' : '$year-${year + 1}');
  }
}

/// "Resultat": a simple resultatrapport and the SIE file for the accountant.
class ResultView extends StatefulWidget {
  const ResultView({super.key});

  @override
  State<ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<ResultView> {
  bool _year = false;
  YearMonth _ym = YearMonth.now();
  int _y = DateTime.now().year;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Månad')),
                ButtonSegment(value: true, label: Text('År')),
              ],
              selected: {_year},
              onSelectionChanged: (s) => setState(() => _year = s.first),
            ),
          ),
          if (_year)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                  tooltip: 'Föregående år', icon: const Icon(AppIcons.chevronLeft), onPressed: () => setState(() => _y--)),
              Text('$_y', style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                  tooltip: 'Nästa år', icon: const Icon(AppIcons.chevronRight), onPressed: () => setState(() => _y++)),
            ])
          else
            MonthSwitcher(value: _ym, onChanged: (v) => setState(() => _ym = v)),
          Expanded(
            child: Reloading<_Data>(
              deps: '$_year $_y ${_ym.title}',
              loader: (c) => _Data.load(c, _year, _y, _ym),
              builder: (context, data) => _ResultBody(data: data),
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
  const _Data(this.period, this.report, this.profile, this.sales, this.invoices, this.online, this.payslips);

  static Future<_Data> load(AppController c, bool year, int y, YearMonth ym) async {
    final start = await c.repo.fiscalStartMonth();
    final p = year ? _Period.year(y, start) : _Period.month(ym, start);
    final sales = await c.repo.dailySalesBetween(p.from, p.to);
    final invoices = await c.repo.invoicesForReports(p.from, p.to);
    final online = await c.repo.onlineSalesBetween(p.from, p.to);
    // Payments made in the period for invoices from before it belong in the SIE file.
    final upToEnd = await c.repo.invoicesBetween('2000-01-01', p.to);
    final report = ResultReport.build(
        title: p.title, fromIso: p.from, toIso: p.to, sales: sales, invoices: invoices, online: online);
    final payslips = await c.repo.payslipsBetween(p.from, p.to);
    return _Data(p, report, await c.repo.profile(), sales, upToEnd, online, payslips);
  }

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
      final email = await showModalBottomSheet<bool>(
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
        .where((i) => i.invoiceDate.compareTo(p.from) >= 0 && i.invoiceDate.compareTo(p.to) <= 0 && i.isIncomplete)
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
      padding: const EdgeInsets.all(16),
      children: [
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
