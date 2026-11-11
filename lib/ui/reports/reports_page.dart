import 'package:flutter/material.dart';

import '../app_icons.dart';

import '../../app/app_controller.dart';
import '../../domain/comparison.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/reports.dart';
import '../../export/table_export.dart';
import '../export_actions.dart';
import '../record_details.dart';
import '../review/online_review_page.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'result_view.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  YearMonth _ym = YearMonth.now();
  int _year = DateTime.now().year;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 40,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: AppTheme.hairline, borderRadius: BorderRadius.circular(12)),
              child: TabBar(
                controller: _tabs,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(10)),
                labelColor: AppTheme.ink,
                unselectedLabelColor: AppTheme.muted,
                labelStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 13),
                tabs: const [Tab(text: 'Månad'), Tab(text: 'År'), Tab(text: 'Jämför'), Tab(text: 'Resultat')],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _MonthView(ym: _ym, onChanged: (v) => setState(() => _ym = v)),
                _YearView(
                  year: _year,
                  onYear: (y) => setState(() => _year = y),
                  onMonth: (m) {
                    setState(() => _ym = YearMonth(_year, m));
                    _tabs.animateTo(0);
                  },
                ),
                const _CompareView(),
                const ResultView(),
              ],
            ),
          ),
        ],
      );
}

class _MonthView extends StatelessWidget {
  final YearMonth ym;
  final ValueChanged<YearMonth> onChanged;
  const _MonthView({required this.ym, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          MonthSwitcher(value: ym, onChanged: onChanged),
          Expanded(
            child: Reloading<MonthData>(
              deps: ym.title,
              loader: (c) => MonthData.load(c, ym),
              builder: (context, m) => MonthlyTable(data: m),
            ),
          ),
        ],
      );
}

class MonthlyTable extends StatelessWidget {
  final MonthData data;
  const MonthlyTable({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final r = data.report;
    final t = Theme.of(context).textTheme;
    final bold = moneyStyle.copyWith(fontWeight: FontWeight.bold);
    DataCell money(Money v, {bool strong = false}) =>
        DataCell(Align(alignment: Alignment.centerRight, child: Text(v.format(unit: false), style: strong ? bold : moneyStyle)));

    final columns = <DataColumn>[
      const DataColumn(label: Text('Datum')),
      for (final c in r.columns) DataColumn(label: Text(c.name), numeric: true),
      const DataColumn(label: Text('Summa'), numeric: true),
      const DataColumn(label: Text('Utgifter'), numeric: true),
      const DataColumn(label: Text('Utg. moms'), numeric: true),
      const DataColumn(label: Text('Ing. moms'), numeric: true),
    ];

    final rows = <DataRow>[
      for (final row in r.rows)
        DataRow(
          onSelectChanged: (_) => _showDay(context, row),
          cells: [
            DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
              Text(row.date),
              if (row.hasSalesDifference)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(AppIcons.warning, size: 16, color: AppTheme.warning),
                ),
            ])),
            for (final c in r.columns) money(row.amounts[c.key] ?? Money.zero),
            money(row.sales, strong: true),
            money(row.expenses),
            money(row.outputVat),
            money(row.inputVat),
          ],
        ),
      DataRow(
        color: WidgetStatePropertyAll(Theme.of(context).colorScheme.surfaceContainerHigh),
        cells: [
          DataCell(Text('Totalt', style: bold)),
          for (final c in r.columns) money(r.columnTotals[c.key] ?? Money.zero, strong: true),
          money(r.totalSales, strong: true),
          money(r.totalExpenses, strong: true),
          money(r.totalOutputVat, strong: true),
          money(r.totalInputVat, strong: true),
        ],
      ),
    ];

    final diff = r.vatDifference;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(data.profile.name.toUpperCase(), style: t.titleMedium),
        Text(r.title.toUpperCase(), style: t.titleSmall),
        const SizedBox(height: 12),
        ExportButtons(
          onPdf: () => exportMonthlyPdf(context, data),
          onExcel: () => exportTableCsv(context, monthlyTable(r)),
          onPrint: () => printMonthly(context, data),
        ),
        const SizedBox(height: 12),
        if (r.rows.isEmpty && r.onlineCount == 0)
          const EmptyState(icon: AppIcons.report, text: 'Inga registreringar den här månaden.')
        else
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (r.rows.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      showCheckboxColumn: false,
                      columnSpacing: 16,
                      headingTextStyle: t.bodySmall,
                      dataTextStyle: t.bodyMedium,
                      columns: columns,
                      rows: rows,
                    ),
                  ),
                _band('Försäljning i kassan', r.totalSales, background: AppTheme.background, color: AppTheme.ink),
                InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => OnlinePaymentsPage(month: YearMonth(r.year, r.month)))),
                  child: _band(
                    r.onlineCount == 0
                        ? 'Onlineförsäljning'
                        : 'Onlineförsäljning (${r.onlineCount} ${r.onlineCount == 1 ? 'betalning' : 'betalningar'})',
                    r.totalOnline,
                    background: AppTheme.onlineTint,
                    color: AppTheme.online,
                    icon: AppIcons.delivery,
                    trailing: AppIcons.chevronRight,
                  ),
                ),
                _band('Total försäljning', r.totalAllSales, background: AppTheme.seed, color: Colors.white, strong: true),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _total('Totala utgifter', r.totalExpenses),
                _total('Total utgående moms (försäljning)', r.totalOutputVat),
                _total('Total ingående moms', r.totalInputVat),
                const Divider(),
                _total(diff.isNegative ? 'Beräknad moms att få tillbaka' : 'Beräknad moms att betala', diff.abs(),
                    strong: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Beräknad moms utifrån de dokument som registrerats i appen. Det är inte en momsdeklaration.',
            style: t.bodySmall),
        if (r.onlineCount > 0) ...[
          const SizedBox(height: 4),
          Text('Onlineförsäljning utan moms på pappret är utbetalning efter provision och ingår inte i momsberäkningen.', style: t.bodySmall),
        ],
      ],
    );
  }

  Widget _band(String label, Money value,
          {required Color background, required Color color, IconData? icon, IconData? trailing, bool strong = false}) =>
      Container(
        color: background,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 16, color: color), const SizedBox(width: 6)],
          Expanded(
            child: Text(label,
                style: TextStyle(color: color, fontWeight: strong ? FontWeight.w500 : FontWeight.w400, fontSize: 13.5)),
          ),
          Text(value.format(compact: true),
              style: moneyStyle.copyWith(color: color, fontWeight: FontWeight.w500, fontSize: 13.5)),
          if (trailing != null) Icon(trailing, size: 16, color: color),
        ]),
      );

  Widget _total(String label, Money v, {bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: strong ? const TextStyle(fontWeight: FontWeight.bold) : null)),
          Text(v.format(), style: strong ? moneyStyle.copyWith(fontWeight: FontWeight.bold) : moneyStyle),
        ]),
      );

  void _showDay(BuildContext context, MonthlyRow row) {
    final sales = data.sales.where((s) => s.businessDate == row.date).toList();
    final invoices = data.invoices.where((i) => i.invoiceDate == row.date).toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(SwedishDates.mediumDay(row.date), style: Theme.of(c).textTheme.titleMedium),
            ),
            for (final s in sales)
              ListTile(
                leading: const Icon(AppIcons.register),
                title: const Text('Z-rapport'),
                subtitle: Text('Moms ${s.outputVat.format()}'),
                trailing: Text(s.detailedTotal.format(), style: moneyStyle),
                onTap: () {
                  Navigator.pop(c);
                  openRecord(context, 'z', s.id!);
                },
              ),
            for (final i in invoices)
              ListTile(
                leading: const Icon(AppIcons.expenses),
                title: Text(i.supplier.isEmpty ? 'Faktura' : i.supplier),
                subtitle: Text('Moms ${i.vatTotal.format()}'),
                trailing: Text(i.total.format(), style: moneyStyle),
                onTap: () {
                  Navigator.pop(c);
                  openRecord(context, 'invoice', i.id!);
                },
              ),
            if (invoices.isEmpty)
              const ListTile(title: Text('Inga fakturor den här dagen.')),
          ],
        ),
      ),
    );
  }
}

class _YearView extends StatelessWidget {
  final int year;
  final ValueChanged<int> onYear;
  final ValueChanged<int> onMonth;
  const _YearView({required this.year, required this.onYear, required this.onMonth});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                  tooltip: 'Föregående år', icon: const Icon(AppIcons.chevronLeft), onPressed: () => onYear(year - 1)),
              Text('$year', style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                  tooltip: 'Nästa år', icon: const Icon(AppIcons.chevronRight), onPressed: () => onYear(year + 1)),
            ],
          ),
          Expanded(
            child: Reloading<(YearReport, BusinessProfile)>(
              deps: year,
              loader: (AppController c) async => (
                const ReportGenerator().yearly(
                  year: year,
                  sales: await c.repo.dailySalesBetween('$year-01-01', '$year-12-31'),
                  invoices: await c.repo.invoicesForReports('$year-01-01', '$year-12-31'),
                  online: await c.repo.onlineSalesBetween('$year-01-01', '$year-12-31'),
                ),
                await c.repo.profile(),
              ),
              builder: (context, data) {
                final (y, profile) = data;
                final bold = moneyStyle.copyWith(fontWeight: FontWeight.bold);
                DataCell money(Money v, {bool strong = false}) => DataCell(
                    Text(v.format(unit: false), style: strong ? bold : moneyStyle));
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ExportButtons(
                      onPdf: () => exportTablePdf(context, yearTable(y), profile),
                      onExcel: () => exportTableCsv(context, yearTable(y)),
                      onPrint: () => printTable(context, yearTable(y), profile),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        showCheckboxColumn: false,
                        columnSpacing: 16,
                        columns: const [
                          DataColumn(label: Text('Månad')),
                          DataColumn(label: Text('Försäljning'), numeric: true),
                          DataColumn(label: Text('Varav online'), numeric: true),
                          DataColumn(label: Text('Utgifter'), numeric: true),
                          DataColumn(label: Text('Utgående moms'), numeric: true),
                          DataColumn(label: Text('Ingående moms'), numeric: true),
                          DataColumn(label: Text('Momsskillnad'), numeric: true),
                        ],
                        rows: [
                          for (final r in y.rows)
                            DataRow(
                              onSelectChanged: (_) => onMonth(r.month),
                              cells: [
                                DataCell(Text(r.monthName)),
                                money(r.sales),
                                money(r.online),
                                money(r.expenses),
                                money(r.outputVat),
                                money(r.inputVat),
                                money(r.vatDifference),
                              ],
                            ),
                          DataRow(
                            color: WidgetStatePropertyAll(Theme.of(context).colorScheme.surfaceContainerHigh),
                            cells: [
                              DataCell(Text('Totalt', style: bold)),
                              money(y.sales, strong: true),
                              money(y.online, strong: true),
                              money(y.expenses, strong: true),
                              money(y.outputVat, strong: true),
                              money(y.inputVat, strong: true),
                              money(y.vatDifference, strong: true),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Momsskillnad = utgående moms − ingående moms. Tryck på en månad för att öppna den.',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                );
              },
            ),
          ),
        ],
      );
}

/// "Jämför": one year against another, month by month, for sales, expenses
/// or moms, as a chart and a table.
class _CompareView extends StatefulWidget {
  const _CompareView();

  @override
  State<_CompareView> createState() => _CompareViewState();
}

class _CompareViewState extends State<_CompareView> {
  int _year = DateTime.now().year;
  late int _other = _year - 1;
  CompareMetric _metric = CompareMetric.sales;

  static Future<YearReport> _load(AppController c, int y) async => const ReportGenerator().yearly(
        year: y,
        sales: await c.repo.dailySalesBetween('$y-01-01', '$y-12-31'),
        invoices: await c.repo.invoicesForReports('$y-01-01', '$y-12-31'),
        online: await c.repo.onlineSalesBetween('$y-01-01', '$y-12-31'),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Reloading<(YearReport, YearReport, BusinessProfile)>(
      deps: '$_year $_other',
      loader: (c) async => (await _load(c, _year), await _load(c, _other), await c.repo.profile()),
      builder: (context, data) {
        final (a, b, profile) = data;
        final cmp = Comparison.of(a, b, _metric);
        final table = comparisonTable(cmp);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              IconButton(
                  tooltip: 'Föregående år',
                  icon: const Icon(AppIcons.chevronLeft),
                  onPressed: () => setState(() {
                        _year--;
                        _other = _year - 1;
                      })),
              Text('$_year', style: t.titleMedium),
              IconButton(
                  tooltip: 'Nästa år',
                  icon: const Icon(AppIcons.chevronRight),
                  onPressed: () => setState(() {
                        _year++;
                        _other = _year - 1;
                      })),
              const Spacer(),
              const Text('mot '),
              DropdownButton<int>(
                value: _other,
                underline: const SizedBox.shrink(),
                items: [
                  for (var y = _year - 1; y >= _year - 5; y--) DropdownMenuItem(value: y, child: Text('$y')),
                ],
                onChanged: (v) => setState(() => _other = v ?? _other),
              ),
            ]),
            Wrap(spacing: 8, children: [
              for (final m in CompareMetric.values)
                ChoiceChip(label: Text(m.label), selected: m == _metric, onSelected: (_) => setState(() => _metric = m)),
            ]),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_metric.label} per månad', style: t.bodySmall),
                  const SizedBox(height: 10),
                  CompareLineChart(
                    current: [for (final r in cmp.rows) r.a.ore / 100],
                    previous: [for (final r in cmp.rows) r.b.ore / 100],
                    semanticLabel: '${_metric.label} per månad $_year jämfört med $_other',
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 14, children: [
                    LegendDot(AppTheme.seed, '$_year'),
                    LegendDot(chartPrevious, '$_other', dashed: true),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Column(children: [
                  _compareRow(context, 'Månad', '$_year', '$_other', 'Skillnad', header: true),
                  for (final r in cmp.rows)
                    _compareRow(context, SwedishDates.capitalize(SwedishDates.months[r.month - 1]), r.a.format(unit: false),
                        r.b.format(unit: false), formatChange(r.changePercent), change: r.changePercent),
                  const Divider(),
                  _compareRow(context, 'Totalt', cmp.totalA.format(unit: false), cmp.totalB.format(unit: false),
                      formatChange(cmp.total.changePercent),
                      change: cmp.total.changePercent, strong: true),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            ExportButtons(
              onPdf: () => exportTablePdf(context, table, profile),
              onExcel: () => exportTableCsv(context, table),
              onPrint: () => printTable(context, table, profile),
            ),
          ],
        );
      },
    );
  }

  /// For expenses a rise is shown as a warning, for sales and moms as normal.
  Widget _compareRow(BuildContext context, String month, String a, String b, String diff,
      {double? change, bool header = false, bool strong = false}) {
    final t = Theme.of(context).textTheme;
    final base = header ? t.bodySmall : (strong ? moneyStyle.copyWith(fontWeight: FontWeight.w600) : moneyStyle);
    final worse = change != null &&
        change.round() != 0 &&
        ((change > 0) == (_metric == CompareMetric.expenses));
    final diffColor = header || change == null || change.round() == 0
        ? null
        : worse
            ? AppTheme.warning
            : AppTheme.seed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(flex: 3, child: Text(month, style: header ? t.bodySmall : t.bodyMedium)),
        Expanded(flex: 3, child: Text(a, textAlign: TextAlign.right, style: base)),
        Expanded(flex: 3, child: Text(b, textAlign: TextAlign.right, style: base)),
        Expanded(flex: 2, child: Text(diff, textAlign: TextAlign.right, style: base?.copyWith(color: diffColor))),
      ]),
    );
  }
}
