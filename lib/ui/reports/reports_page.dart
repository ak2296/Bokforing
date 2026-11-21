import 'package:flutter/material.dart';

import '../app_icons.dart';

import '../../app/app_controller.dart';
import '../../data/accounting_settings.dart';
import '../../data/bank_match_store.dart';
import '../../domain/cash_summary.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/report_period.dart';
import '../../domain/reports.dart';
import '../../export/table_export.dart';
import '../bank_match_page.dart';
import '../export_actions.dart';
import '../record_details.dart';
import '../review/online_review_page.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/report_charts.dart';
import '../widgets/common.dart';
import '../widgets/ledger_parts.dart' show HeroStat;
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
  // Period (Månad | År), Moms, Kontroll, Bokslut, Redovisning. Jämför är en knapp på startsidan.
  late final TabController _tabs = TabController(length: 5, vsync: this)..addListener(_changed);
  YearMonth _ym = YearMonth.now();
  int _year = DateTime.now().year;

  /// One period for Resultat, Balans and Redovisning, so they always agree.
  ReportPeriod? _period;

  /// Inside Bokslut: 0 Resultat, 1 Balans.
  int _resBal = 0;

  /// Inside Period: 0 Månad, 1 År.
  int _monthYear = 0;
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

  /// Two big buttons that switch what a tab shows (Resultat | Balans, Månad | År).
  Widget _switchRow(List<(String, Color)> items, int selected, ValueChanged<int> onTap) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(children: [
          for (final (i, item) in items.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Material(
                color: selected == i ? item.$2 : Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: item.$2, width: 1.5)),
                child: InkWell(
                  customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () => onTap(i),
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    child: Text(item.$1,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: selected == i ? Colors.white : item.$2)),
                  ),
                ),
              ),
            ),
          ],
        ]),
      );

  Widget _periodView() => Column(children: [
        _switchRow([('Månad', AppTheme.seed), ('År', AppTheme.sales)], _monthYear, (i) => setState(() => _monthYear = i)),
        Expanded(
          child: _monthYear == 0
              ? _MonthView(ym: _ym, onChanged: (v) => setState(() => _ym = v))
              : _YearView(
                  year: _year,
                  onYear: (y) => setState(() => _year = y),
                  onMonth: (m) => setState(() {
                    _ym = YearMonth(_year, m);
                    _monthYear = 0;
                  }),
                ),
        ),
      ]);

  Widget _periodTab(ResultMode mode) {
    final period = _period;
    if (period == null) return const Center(child: CircularProgressIndicator());
    return ResultView(period: period, onChanged: (v) => setState(() => _period = v), mode: mode, ym: _ym);
  }

  Widget _resBalView() {
    final period = _period;
    if (period == null) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      _switchRow([('Resultat', AppTheme.pumpkin), ('Balans', AppTheme.balance)], _resBal, (i) => setState(() => _resBal = i)),
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
                _periodView(),
                _periodTab(ResultMode.moms),
                _periodTab(ResultMode.kontroll),
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
      ('Period', AppTheme.seed, 10),
      ('Moms', AppTheme.compare, 9),
      ('Kontroll', AppTheme.warning, 12),
      ('Bokslut', AppTheme.pumpkin, 11),
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
            child: Reloading<(MonthData, BankMatchFlags)>(
              deps: ym.title,
              loader: (c) async => (await MonthData.load(c, ym), await loadBankMatch(c.repo)),
              builder: (context, d) => MonthlyTable(data: d.$1, flags: d.$2),
            ),
          ),
        ],
      );
}

/// "Kassa denna månad (netto)": cash and card in from the Z-reports, out by how each
/// invoice was paid. Net, not a balance.
class _CashCard extends StatelessWidget {
  final CashSummary s;
  const _CashCard(this.s);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget row(String label, Money v, {String? sub, bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: strong ? t.titleSmall : t.bodyMedium),
                if (sub != null) Text(sub, style: t.bodySmall),
              ]),
            ),
            Text(v.format(compact: true),
                style: (strong ? t.titleSmall : t.bodyMedium)
                    ?.merge(moneyStyle)
                    .copyWith(color: strong ? (v.isNegative ? AppTheme.danger : AppTheme.seed) : null)),
          ]),
        );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('KASSA DENNA MÅNAD (NETTO)', style: t.labelMedium?.copyWith(color: AppTheme.muted, letterSpacing: 0.4)),
          row('Kontant in', s.cashIn, sub: 'Z-rapporter med kontant och kort: ${s.zDaysWithPayments} av ${s.zDays}'),
          row('Kontant ut', -s.cashOut, sub: 'utgifter betalda kontant'),
          row('Kontant kvar', s.cashLeft, strong: true),
          Divider(height: 14, color: AppTheme.hairline),
          row('Kort och Swish in', s.cardIn),
          row('Bank / kort ut', -s.bankOut, sub: 'utgifter betalda med bank eller kort'),
          row('Bank / kort netto', s.bankNet, strong: true),
          const SizedBox(height: 4),
          Text(
              'Netto, inte saldo: appen har ingen ingående kassa, och kontantinsättningar, löner och uttag finns inte i den.${s.zDaysWithoutPayments > 0 ? ' ${s.zDaysWithoutPayments} Z-rapporter saknar kontant- och kortbelopp.' : ''}',
              style: t.bodySmall),
        ]),
      ),
    );
  }
}

class MonthlyTable extends StatelessWidget {
  final MonthData data;

  /// What the last bank file said, for the "Z mot bank" chip.
  final BankMatchFlags flags;
  const MonthlyTable({super.key, required this.data, this.flags = const BankMatchFlags()});

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
    final cash = CashSummary.of(data.sales, data.invoices);
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
          extraChips: [
            HeroStat('Kontant kvar', cash.cashLeft.format(compact: true)),
            HeroStat('Bank / kort netto', cash.bankNet.format(compact: true)),
            HeroStat('Z mot bank', flags.zText(data.sales),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BankMatchPage(invoices: false)))),
          ],
        ),
        const SizedBox(height: 12),
        _CashCard(cash),
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

