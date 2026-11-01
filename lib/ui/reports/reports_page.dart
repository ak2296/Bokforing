import 'package:flutter/material.dart';

import '../app_icons.dart';

import '../../app/app_controller.dart';
import '../../domain/dates.dart';
import '../../domain/money.dart';
import '../../domain/reports.dart';
import '../export_actions.dart';
import '../record_details.dart';
import '../review/online_review_page.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
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
                indicator: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                labelColor: AppTheme.ink,
                unselectedLabelColor: AppTheme.muted,
                labelStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 13),
                tabs: const [Tab(text: 'Månad'), Tab(text: 'Årsöversikt')],
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
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(AppIcons.pdf),
                label: const Text('Exportera PDF'),
                onPressed: () => exportMonthlyPdf(context, data),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(AppIcons.print),
                label: const Text('Skriv ut'),
                onPressed: () => printMonthly(context, data),
              ),
            ),
          ],
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
          Text('Onlineförsäljning är utbetalning efter provision och ingår inte i momsberäkningen.', style: t.bodySmall),
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
            child: Reloading<YearReport>(
              deps: year,
              loader: (AppController c) async => const ReportGenerator().yearly(
                year: year,
                sales: await c.repo.dailySalesBetween('$year-01-01', '$year-12-31'),
                invoices: await c.repo.invoicesBetween('$year-01-01', '$year-12-31'),
                online: await c.repo.onlineSalesBetween('$year-01-01', '$year-12-31'),
              ),
              builder: (context, y) {
                final bold = moneyStyle.copyWith(fontWeight: FontWeight.bold);
                DataCell money(Money v, {bool strong = false}) => DataCell(
                    Text(v.format(unit: false), style: strong ? bold : moneyStyle));
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
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
