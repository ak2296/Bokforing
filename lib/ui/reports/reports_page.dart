import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../domain/dates.dart';
import '../../domain/money.dart';
import '../../domain/reports.dart';
import '../export_actions.dart';
import '../record_details.dart';
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
          TabBar(controller: _tabs, tabs: const [Tab(text: 'Månad'), Tab(text: 'Årsöversikt')]),
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
                  child: Icon(Icons.warning_amber_rounded, size: 16, color: AppTheme.warning),
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
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Exportera PDF'),
                onPressed: () => exportMonthlyPdf(context, data),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.print_outlined),
                label: const Text('Skriv ut'),
                onPressed: () => printMonthly(context, data),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (r.rows.isEmpty)
          const EmptyState(icon: Icons.table_chart_outlined, text: 'Inga registreringar den här månaden.')
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columnSpacing: 16,
              headingTextStyle: t.labelLarge,
              columns: columns,
              rows: rows,
            ),
          ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _total('Total försäljning', r.totalSales),
                _total('Total utgifter', r.totalExpenses),
                _total('Total moms på försäljning (utgående)', r.totalOutputVat),
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
      ],
    );
  }

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
                leading: const Icon(Icons.point_of_sale_outlined),
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
                leading: const Icon(Icons.receipt_long_outlined),
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
                  tooltip: 'Föregående år', icon: const Icon(Icons.chevron_left), onPressed: () => onYear(year - 1)),
              Text('$year', style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                  tooltip: 'Nästa år', icon: const Icon(Icons.chevron_right), onPressed: () => onYear(year + 1)),
            ],
          ),
          Expanded(
            child: Reloading<YearReport>(
              deps: year,
              loader: (AppController c) async => const ReportGenerator().yearly(
                year: year,
                sales: await c.repo.dailySalesBetween('$year-01-01', '$year-12-31'),
                invoices: await c.repo.invoicesBetween('$year-01-01', '$year-12-31'),
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
