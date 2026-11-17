import 'package:flutter/material.dart';

import '../app_icons.dart';

import '../../app/app_controller.dart';
import '../../data/accounting_settings.dart';
import '../../domain/comparison.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/report_period.dart';
import '../../domain/reports.dart';
import '../../export/table_export.dart';
import '../export_actions.dart';
import '../record_details.dart';
import '../review/online_review_page.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/report_charts.dart';
import '../widgets/common.dart';
import 'report_hero.dart';
import 'result_card.dart';
import 'result_view.dart';
import '../widgets/blur_overlay.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> with SingleTickerProviderStateMixin {
  // Månad, År, Jämför, Res/Bal, Redovisning.
  late final TabController _tabs = TabController(length: 5, vsync: this)..addListener(_changed);
  YearMonth _ym = YearMonth.now();
  int _year = DateTime.now().year;

  /// One period for Resultat, Balans and Redovisning, so they always agree.
  ReportPeriod? _period;

  /// Inside Res/Bal: 0 Resultat, 1 Balans.
  int _resBal = 0;
  bool _started = false;

  void _changed() {
    if (mounted) setState(() {});
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
    if (mounted) setState(() => _period = ReportPeriod.containing(acc.kind, DateTime.now(), start));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Widget _resBalView() {
    final period = _period;
    if (period == null) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(children: [
          for (final (i, label, color) in [(0, 'Resultat', AppTheme.pumpkin), (1, 'Balans', AppTheme.balance)]) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Material(
                color: _resBal == i ? color : Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color, width: 1.5)),
                child: InkWell(
                  customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () => setState(() => _resBal = i),
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    child: Text(label,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _resBal == i ? Colors.white : color)),
                  ),
                ),
              ),
            ),
          ],
        ]),
      ),
      Expanded(
        child: ResultView(
          period: period,
          onChanged: (v) => setState(() => _period = v),
          mode: _resBal == 0 ? ResultMode.resultat : ResultMode.balans,
          ym: _ym,
        ),
      ),
    ]);
  }

  Widget _accountingView() {
    final period = _period;
    if (period == null) return const Center(child: CircularProgressIndicator());
    return ResultView(
      period: period,
      onChanged: (v) => setState(() => _period = v),
      mode: ResultMode.redovisning,
      ym: _ym,
    );
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: _ReportTabBar(controller: _tabs),
          ),
          Expanded(
            // The pages swipe, so these tabs change by tap only.
            child: TabBarView(
              controller: _tabs,
              physics: const NeverScrollableScrollPhysics(),
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
                _resBalView(),
                _accountingView(),
              ],
            ),
          ),
        ],
      );
}

/// The five report tabs as one pill: the chosen tab is filled with the colour of
/// its page's hero, the others show a small dot in it. The widths follow the
/// words, so "Redovisning" fits and "År" stays small.
class _ReportTabBar extends StatelessWidget {
  final TabController controller;
  const _ReportTabBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final tabs = <(String, Color, int)>[
      ('Månad', AppTheme.seed, 11),
      ('År', AppTheme.sales, 6),
      ('Jämför', AppTheme.compare, 11),
      ('Res/Bal', AppTheme.pumpkin, 11),
      ('Redovisning', AppTheme.accounting, 16),
    ];
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppTheme.hairline, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        for (final (i, tab) in tabs.indexed)
          Expanded(
            flex: tab.$3,
            child: Semantics(
              button: true,
              selected: controller.index == i,
              label: tab.$1,
              child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: () => controller.animateTo(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: controller.index == i ? tab.$2 : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (controller.index != i) ...[
                        Container(width: 5, height: 5, decoration: BoxDecoration(color: tab.$2, shape: BoxShape.circle)),
                        const SizedBox(width: 3),
                      ],
                      Text(tab.$1,
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12.5,
                            fontWeight: controller.index == i ? FontWeight.w600 : FontWeight.w500,
                            color: controller.index == i ? Colors.white : AppTheme.muted,
                          )),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
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
                Padding(
                  padding: const EdgeInsets.only(left: 4),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
      children: [
        ReportHero(
          color: AppTheme.seed,
          label: 'Total försäljning, ${r.title}',
          value: r.totalAllSales.format(),
          chips: [
            ('Utgifter', r.totalExpenses.format(compact: true)),
            ('Utg. moms', r.totalOutputVat.format(compact: true)),
            (r.vatDifference.isNegative ? 'Moms tillbaka' : 'Moms att betala', r.vatDifference.abs().format(compact: true)),
          ],
        ),
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
        ResultSummaryCard(
          title: 'Resultat',
          from: '${r.year}-${r.month.toString().padLeft(2, '0')}-01',
          to: SwedishDates.iso(DateTime(r.year, r.month + 1, 0)),
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
    final invoices = data.invoices.where((i) => i.bookingDate == row.date).toList();
    showBlurSheet<void>(
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

/// The year's result and moms month by month.
class _YearCharts extends StatelessWidget {
  final YearReport y;
  const _YearCharts(this.y);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final labels = [for (final r in y.rows) SwedishDates.shortMonths[r.month - 1]];
    // Excl. moms, like the Resultat tab: sales and costs without the moms in them.
    final result = [for (final r in y.rows) ((r.sales - r.outputVat) - (r.expenses - r.inputVat)).ore / 100];
    Widget panel(String title, Widget child) => Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: t.bodySmall),
              const SizedBox(height: 10),
              child,
            ]),
          ),
        );
    return Column(children: [
      panel(
        'Resultat per månad, exkl. moms',
        SignedBarChart(labels: labels, values: result, semanticLabel: 'Resultat för varje månad under året'),
      ),
      panel(
        'Moms per månad',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PairedBarChart(
            labels: labels,
            first: [for (final r in y.rows) r.outputVat.ore / 100],
            second: [for (final r in y.rows) r.inputVat.ore / 100],
            semanticLabel: 'Utgående och ingående moms för varje månad under året',
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 14, children: [
            LegendDot(AppTheme.seed, 'Utgående moms'),
            LegendDot(chartSecond, 'Ingående moms'),
          ]),
        ]),
      ),
    ]);
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
                  children: [
                    ReportHero(
                      color: AppTheme.sales,
                      label: 'Försäljning $year',
                      value: y.sales.format(),
                      chips: [
                        ('Utgifter', y.expenses.format(compact: true)),
                        ('Moms netto', y.vatDifference.format(compact: true)),
                        ('Bästa månad', y.sales.isZero ? '–' : SwedishDates.capitalize(y.rows.reduce((a, b) => b.sales > a.sales ? b : a).monthName)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ExportButtons(
                      onPdf: () => exportTablePdf(context, yearTable(y), profile),
                      onExcel: () => exportTableCsv(context, yearTable(y)),
                      onPrint: () => printTable(context, yearTable(y), profile),
                    ),
                    const SizedBox(height: 12),
                    _YearCharts(y),
                    const SizedBox(height: 4),
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
                    const SizedBox(height: 16),
                    ResultSummaryCard(
                      title: 'Året $year',
                      from: '$year-01-01',
                      to: '$year-12-31',
                      months: 12,
                      vat: y.vatDifference,
                    ),
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

  /// Sales in the slate blue of Försäljning, costs in pumpkin, moms in the overview green.
  Color get _accent => switch (_metric) {
        CompareMetric.sales => AppTheme.sales,
        CompareMetric.expenses => AppTheme.pumpkin,
        CompareMetric.vat => AppTheme.seed,
      };

  /// For expenses a rise is a warning, for sales and moms it is normal.
  bool _worse(double? change) =>
      change != null && change.round() != 0 && ((change > 0) == (_metric == CompareMetric.expenses));

  String get _subject => switch (_metric) {
        CompareMetric.sales => 'Försäljningen',
        CompareMetric.expenses => 'Utgifterna',
        CompareMetric.vat => 'Momsen att betala',
      };

  @override
  Widget build(BuildContext context) {
    return Reloading<(YearReport, YearReport, BusinessProfile)>(
      deps: '$_year $_other',
      loader: (c) async => (await _load(c, _year), await _load(c, _other), await c.repo.profile()),
      builder: (context, data) {
        final (a, b, profile) = data;
        final cmp = Comparison.of(a, b, _metric);
        final table = comparisonTable(cmp);
        final now = DateTime.now();
        // While the year is not over, both years are compared over the same months.
        final upTo = _year == now.year ? now.month : 12;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
          children: [
            _yearPicker(context, now),
            const SizedBox(height: 10),
            _metricSwitch(),
            const SizedBox(height: 12),
            _hero(context, cmp, upTo),
            ..._insights(context, cmp, upTo),
            const SizedBox(height: 10),
            _chartCard(context, cmp),
            const SizedBox(height: 10),
            _monthList(context, cmp, upTo),
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

  Widget _yearPicker(BuildContext context, DateTime now) {
    final t = Theme.of(context).textTheme;
    final years = {for (var y = now.year; y >= now.year - 6; y--) y, _other}.where((y) => y != _year).toList()
      ..sort((x, y) => y.compareTo(x));
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        child: Row(children: [
          IconButton(
              tooltip: 'Föregående år',
              icon: const Icon(AppIcons.chevronLeft),
              onPressed: () => setState(() {
                    _year--;
                    _other = _year - 1;
                  })),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Period', style: t.bodySmall),
            Text('$_year', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          ]),
          IconButton(
              tooltip: 'Nästa år',
              icon: const Icon(AppIcons.chevronRight),
              onPressed: () => setState(() {
                    _year++;
                    _other = _year - 1;
                  })),
          Text('mot', style: t.bodySmall),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Jämförår', style: t.bodySmall),
            DropdownButton<int>(
              value: _other,
              isDense: true,
              underline: const SizedBox.shrink(),
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: AppTheme.ink),
              items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
              onChanged: (v) => setState(() => _other = v ?? _other),
            ),
          ]),
          const Spacer(),
          IconButton.filledTonal(
            tooltip: 'Byt plats på åren',
            icon: const Icon(AppIcons.swap),
            onPressed: () => setState(() {
              final y = _year;
              _year = _other;
              _other = y;
            }),
          ),
        ]),
      ),
    );
  }

  Widget _metricSwitch() => SegmentedButton<CompareMetric>(
        expandedInsets: EdgeInsets.zero,
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppTheme.compare : null),
          foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
        ),
        segments: [
          for (final m in CompareMetric.values)
            ButtonSegment(value: m, label: Text(m == CompareMetric.vat ? 'Moms' : m.label)),
        ],
        selected: {_metric},
        onSelectionChanged: (v) => setState(() => _metric = v.first),
      );

  /// The answer first: how much more or less, over the same months in both years.
  Widget _hero(BuildContext context, Comparison cmp, int upTo) {
    final t = Theme.of(context).textTheme;
    final period = cmp.totalUpTo(upTo);
    final diff = period.a - period.b;
    final change = period.changePercent;
    final String sentence;
    if (change == null) {
      sentence = 'Inget att jämföra med $_other.';
    } else if (diff.isZero) {
      sentence = '$_subject är lika stor som $_other.';
    } else {
      final more = !diff.isNegative;
      sentence = '$_subject är ${more ? 'högre' : 'lägre'} än $_other: ${Money(diff.ore.abs()).format()} ${more ? 'mer' : 'mindre'}.';
    }
    final label = upTo < 12 ? 'Jan–${SwedishDates.shortMonths[upTo - 1]}, samma period båda åren' : 'Hela året';
    const on = Colors.white;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.compare, Color.lerp(AppTheme.compare, Colors.black, 0.28)!],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(color: on.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
          child: Text(label, style: t.labelSmall?.copyWith(color: on)),
        ),
        const SizedBox(height: 8),
        Text(formatChange(change), style: t.displaySmall?.copyWith(color: on, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(sentence, style: t.bodyMedium?.copyWith(color: on.withValues(alpha: 0.92))),
        const SizedBox(height: 14),
        Container(height: 1, color: on.withValues(alpha: 0.25)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _heroFigure(t, '$_year', period.a)),
          Expanded(child: _heroFigure(t, '$_other', period.b)),
        ]),
      ]),
    );
  }

  Widget _heroFigure(TextTheme t, String year, Money value) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(year, style: t.labelMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
        Text(value.format(),
            style: t.titleMedium?.merge(moneyStyle).copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
      ]);

  List<Widget> _insights(BuildContext context, Comparison cmp, int upTo) {
    final rise = cmp.biggestRise(upTo);
    final fall = cmp.biggestFall(upTo);
    if (rise == null && fall == null) return const [];
    final t = Theme.of(context).textTheme;
    Widget tile(String title, CompareRow? r) => Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: t.bodySmall),
                const SizedBox(height: 2),
                if (r == null)
                  Text('–', style: t.titleSmall)
                else
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${SwedishDates.capitalize(SwedishDates.months[r.month - 1])} '),
                      TextSpan(
                          text: formatChange(r.changePercent),
                          style: TextStyle(color: _worse(r.changePercent) ? AppTheme.warning : AppTheme.seed)),
                    ]),
                    style: t.titleSmall,
                  ),
              ]),
            ),
          ),
        );
    return [
      const SizedBox(height: 10),
      Row(children: [tile('Störst ökning', rise), const SizedBox(width: 10), tile('Största minskning', fall)]),
    ];
  }

  Widget _chartCard(BuildContext context, Comparison cmp) {
    final t = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_metric.label} per månad', style: t.bodySmall),
          const SizedBox(height: 10),
          CompareLineChart(
            color: _accent,
            current: [for (final r in cmp.rows) r.a.ore / 100],
            previous: [for (final r in cmp.rows) r.b.ore / 100],
            semanticLabel: '${_metric.label} per månad $_year jämfört med $_other',
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 14, children: [
            LegendDot(_accent, '$_year'),
            LegendDot(chartPrevious, '$_other', dashed: true),
          ]),
        ]),
      ),
    );
  }

  /// Twelve months, each with two bars (this year, the other year), both
  /// figures and the change; months still to come are dimmed.
  Widget _monthList(BuildContext context, Comparison cmp, int upTo) {
    final t = Theme.of(context).textTheme;
    var top = 0;
    for (final r in cmp.rows) {
      if (r.a.ore.abs() > top) top = r.a.ore.abs();
      if (r.b.ore.abs() > top) top = r.b.ore.abs();
    }
    final period = cmp.totalUpTo(upTo);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Månad för månad', style: t.bodySmall),
          const SizedBox(height: 4),
          for (final r in cmp.rows)
            _monthRow(context, SwedishDates.capitalize(SwedishDates.shortMonths[r.month - 1]), r, top, dim: r.month > upTo),
          const Divider(height: 14),
          _monthRow(context, upTo < 12 ? 'Jan–${SwedishDates.shortMonths[upTo - 1]}' : 'Totalt', period, 0, strong: true),
        ]),
      ),
    );
  }

  Widget _monthRow(BuildContext context, String label, CompareRow r, int top, {bool dim = false, bool strong = false}) {
    final t = Theme.of(context).textTheme;
    final empty = r.a.isZero && r.b.isZero;
    final change = r.changePercent;
    final flat = change == null || change.round() == 0;
    final worse = _worse(change);
    final pillColor = flat ? AppTheme.muted : (worse ? AppTheme.warning : AppTheme.seed);
    final pillTint = flat ? Colors.transparent : (worse ? AppTheme.warningTint : AppTheme.tint);
    Widget bar(Money m, Color c) => ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LayoutBuilder(
            builder: (context, box) => Align(
              alignment: Alignment.centerLeft,
              child: Container(width: box.maxWidth * (m.ore.abs() / top).clamp(0.0, 1.0), height: 6, color: c),
            ),
          ),
        );
    final money = moneyStyle.copyWith(fontSize: 12);
    return Opacity(
      opacity: dim ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(
              width: 50,
              child: Text(label, style: strong ? t.bodyMedium?.copyWith(fontWeight: FontWeight.w600) : t.bodyMedium)),
          Expanded(
            child: top == 0
                ? const SizedBox.shrink()
                : Column(children: [bar(r.a, _accent), const SizedBox(height: 3), bar(r.b, chartPrevious)]),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 66,
            child: empty
                ? Text('–', textAlign: TextAlign.right, style: money)
                : Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(r.a.format(unit: false), style: strong ? money.copyWith(fontWeight: FontWeight.w600) : money),
                    Text(r.b.format(unit: false), style: money.copyWith(color: AppTheme.muted)),
                  ]),
          ),
          const SizedBox(width: 8),
          Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(color: pillTint, borderRadius: BorderRadius.circular(10)),
            child: Text(dim ? '' : formatChange(change),
                textAlign: TextAlign.center, style: t.labelMedium?.copyWith(color: pillColor, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}
