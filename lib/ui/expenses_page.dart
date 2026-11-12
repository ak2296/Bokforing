import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../domain/cost_types.dart';
import '../domain/dates.dart';
import '../domain/invoice_filter.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'app_icons.dart';
import 'bank_import_page.dart';
import 'incomplete_page.dart';
import 'record_details.dart';
import 'theme.dart';
import 'unpaid_page.dart';
import 'widgets/common.dart';
import 'widgets/ledger_parts.dart';

/// Colours for expenses, matching the expenses bars on Översikt.
const _expense = AppTheme.pumpkin;
const _expenseTint = AppTheme.pumpkinTint;

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  YearMonth _ym = YearMonth.now();
  InvoiceFilter _filter = const InvoiceFilter();
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setFilter(InvoiceFilter f) => setState(() => _filter = f);

  Widget _searchField(BuildContext context) => TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Sök i alla månader: leverantör, nummer, typ',
          prefixIcon: const Icon(AppIcons.search),
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_filter.active)
              IconButton(
                tooltip: 'Rensa sökningen',
                icon: const Icon(AppIcons.close),
                onPressed: () {
                  _search.clear();
                  FocusScope.of(context).unfocus();
                  _setFilter(const InvoiceFilter());
                },
              ),
            IconButton(
              tooltip: 'Filtrera',
              icon: Icon(AppIcons.filter,
                  color: _filter.supplier != null || _filter.costType != null || _filter.from != null
                      ? AppTheme.seed
                      : null),
              onPressed: () async {
                final f = await showFilterSheet(context, _filter);
                if (f != null) _setFilter(f);
              },
            ),
          ]),
        ),
        onChanged: (v) => _setFilter(_filter.copyWith(query: v)),
      );

  List<Widget> _filterChips() => [
        if (_filter.supplier != null)
          InputChip(
            label: Text(_filter.supplier!),
            onDeleted: () => _setFilter(_filter.copyWith(clearSupplier: true)),
          ),
        if (_filter.costType != null)
          InputChip(
            label: Text(CostType.labelFor(_filter.costType!)),
            onDeleted: () => _setFilter(_filter.copyWith(clearCostType: true)),
          ),
        if (_filter.from != null || _filter.to != null)
          InputChip(
            label: Text('${_filter.from ?? '…'} – ${_filter.to ?? '…'}'),
            onDeleted: () => _setFilter(_filter.copyWith(clearDates: true)),
          ),
      ];

  // Every invoice is loaded with the month, so typing filters in place and
  // the search field keeps its focus (no reload between letters).
  @override
  Widget build(BuildContext context) => Reloading<(MonthData, List<Invoice>, List<Invoice>)>(
        deps: _ym.title,
        loader: (c) async => (
          await MonthData.load(c, _ym),
          await c.repo.unpaidInvoices(),
          await c.repo.invoicesBetween('0000-01-01', '9999-12-31'),
        ),
        builder: (context, data) {
          final (m, unpaid, all) = data;
          final r = m.report;
          final byType = <String, Money>{};
          for (final i in m.invoices) {
            final label = CostType.labelFor(i.costType);
            final shown = m.rounded ? i.roundedToKr() : i;
            byType[label] = (byType[label] ?? Money.zero) + (shown.total - shown.vatTotal);
          }
          // Lönebesked count as Löner and Sociala avgifter.
          for (final p in m.payslips) {
            for (final e in p.asExpenses()) {
              final shown = m.rounded ? e.roundedToKr() : e;
              final label = CostType.labelFor(e.costType);
              byType[label] = (byType[label] ?? Money.zero) + shown.total;
            }
          }
          final parts = byType.entries.map((e) => (e.key, e.value)).toList()
            ..sort((a, b) => b.$2.ore.compareTo(a.$2.ore));
          // Invoices, receipts and lönebesked in one list, newest first.
          final rows = <(String, Widget)>[
            for (final inv in m.invoices) (inv.invoiceDate, _invoiceRow(context, inv, rounded: m.rounded)),
            for (final p in m.payslips) (p.payoutDate, _payslipRow(context, p, rounded: m.rounded)),
          ]..sort((a, b) => b.$1.compareTo(a.$1));
          final unpaidThisMonth = m.invoices.where((i) => !i.paid).length;
          final incomplete = m.invoices.where((i) => i.isIncomplete).length;
          final searching = _filter.active;
          final hits = all.where(_filter.matches).toList()..sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              MonthPill(
                title: _ym.title,
                onPrevious: () => setState(() => _ym = _ym.previous),
                onNext: () => setState(() => _ym = _ym.next),
              ),
              const SizedBox(height: 12),
              SummaryHero(
                label: 'Utgifter',
                total: r.totalExpenses,
                icon: AppIcons.expenses,
                color: _expense,
                stats: [
                  ('Ingående moms', r.totalInputVat.format(compact: true)),
                  ('Fakturor', '${m.invoices.length}'),
                  ('Obetalda', '$unpaidThisMonth'),
                ],
              ),
              const SizedBox(height: 10),
              _UnpaidTile(unpaid),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.seed,
                  side: BorderSide(color: AppTheme.seed, width: 1.5),
                ),
                icon: const Icon(AppIcons.file, size: 18),
                label: const Text('Matcha betalningar från bankfil'),
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BankImportPage())),
              ),
              if (incomplete > 0) ...[
                const SizedBox(height: 10),
                IncompleteNotice(count: incomplete, from: _ym.firstDay, to: _ym.lastDay, period: _ym.title),
              ],
              if (parts.isNotEmpty) ...[
                const SectionTitle('Per kostnadstyp', trailing: 'exkl. moms'),
                ShareBar(parts: parts, colors: costPalette),
              ],
              SectionTitle('Fakturor och kvitton',
                  trailing: searching
                      ? '${hits.length} träffar · ${Money.sum(hits.map((i) => m.rounded ? i.total.roundedToKr() : i.total)).format(compact: true)}'
                      : (rows.isEmpty ? null : '${rows.length} st')),
              _searchField(context),
              const SizedBox(height: 8),
              if (_filterChips().isNotEmpty) ...[
                Wrap(spacing: 6, runSpacing: 6, children: _filterChips()),
                const SizedBox(height: 8),
              ],
              if (searching)
                hits.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('Inga fakturor eller kvitton matchar sökningen.')),
                      )
                    : LedgerCard(children: [for (final inv in hits) _invoiceRow(context, inv, rounded: m.rounded)])
              else if (rows.isEmpty)
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                    child: Column(children: [
                      const IconTile(AppIcons.expenses, background: _expenseTint, color: _expense),
                      const SizedBox(height: 10),
                      Text('Inga fakturor registrerade den här månaden.',
                          textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                )
              else
                LedgerCard(children: [for (final r in rows) r.$2]),
            ],
          );
        },
      );
}

/// A lönebesked in the list: the employee's name (never the personnummer) and
/// what it costs the company, bruttolön plus arbetsgivaravgift.
Widget _payslipRow(BuildContext context, Payslip p, {bool rounded = false}) => LedgerRow(
      isoDate: p.payoutDate,
      title: p.employeeName.isEmpty ? 'Lönebesked' : p.employeeName,
      subtitle: [
        'Lönebesked',
        'Löner och sociala avgifter',
        if (p.periodFrom != null && p.periodFrom!.length >= 7) 'period ${p.periodFrom!.substring(0, 7)}',
      ].join(' · '),
      amount: rounded ? p.cost.roundedToKr() : p.cost,
      badgeBackground: _expenseTint,
      badgeColor: _expense,
      chips: [StatusChip('Lönebesked', color: AppTheme.seed, background: AppTheme.tint)],
      onTap: () => openRecord(context, 'payslip', p.id!),
    );

/// One invoice row. With [rounded], summa and moms are shown in whole kronor;
/// what is missing on the invoice is always judged on the exact invoice.
Widget _invoiceRow(BuildContext context, Invoice inv, {bool rounded = false}) => LedgerRow(
      isoDate: inv.invoiceDate,
      title: inv.supplier.isNotEmpty ? inv.supplier : (inv.total.isNegative ? 'Kreditnota' : 'Faktura'),
      subtitle: [
        if (CostType.byKey(inv.costType) != null) CostType.labelFor(inv.costType),
        if (inv.invoiceNumber.isNotEmpty) 'Nr ${inv.invoiceNumber}',
        'Moms ${(rounded ? inv.vatTotal.roundedToKr() : inv.vatTotal).format(compact: true)}',
      ].join(' · '),
      amount: rounded ? inv.total.roundedToKr() : inv.total,
      badgeBackground: _expenseTint,
      badgeColor: _expense,
      chips: [
        if (inv.total.isNegative) StatusChip('Kreditnota', color: AppTheme.seed, background: AppTheme.tint),
        if (!inv.paid) _dueChip(inv),
        if (inv.isIncomplete)
          StatusChip('Fyll i: ${inv.missingFields.join(', ')}', color: AppTheme.fix, background: AppTheme.fixTint),
      ],
      onTap: () => openRecord(context, 'invoice', inv.id!),
    );

Widget _dueChip(Invoice inv) {
  final days = daysUntil(inv.dueDate);
  if (days == null) return const StatusChip('Obetald');
  if (days < 0) return const StatusChip('Förfallen', color: Color(0xFFB3261E), background: Color(0xFFFDECEA));
  if (days == 0) return const StatusChip('Förfaller i dag');
  return StatusChip('Obetald · $days d kvar');
}

/// Supplier, cost type and date range. Returns the new filter, or null when
/// the sheet is closed without "Visa".
Future<InvoiceFilter?> showFilterSheet(BuildContext context, InvoiceFilter current) async {
  final all = await AppScope.read(context).repo.invoicesBetween('0000-01-01', '9999-12-31');
  final suppliers = {
    for (final i in all)
      if (i.supplier.trim().isNotEmpty) i.supplier.trim(),
  }.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  if (!context.mounted) return null;
  var f = current;
  return showModalBottomSheet<InvoiceFilter>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setSheet) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Filtrera fakturor', style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: suppliers.contains(f.supplier) ? f.supplier : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Leverantör'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Alla leverantörer')),
                for (final s in suppliers) DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setSheet(() => f = v == null ? f.copyWith(clearSupplier: true) : f.copyWith(supplier: v)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: f.costType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Kostnadstyp'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Alla typer')),
                const DropdownMenuItem(value: '', child: Text('Ej vald kostnadstyp')),
                for (final t in CostType.all) DropdownMenuItem(value: t.key, child: Text(t.label)),
              ],
              onChanged: (v) => setSheet(() => f = v == null ? f.copyWith(clearCostType: true) : f.copyWith(costType: v)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(AppIcons.calendar),
              label: Text(f.from == null && f.to == null ? 'Välj datum (från – till)' : '${f.from} – ${f.to}'),
              onPressed: () async {
                final range = await showDateRangePicker(
                  context: c,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  helpText: 'Fakturadatum',
                );
                if (range != null) {
                  setSheet(() => f = f.copyWith(from: SwedishDates.iso(range.start), to: SwedishDates.iso(range.end)));
                }
              },
            ),
            if (f.from != null)
              TextButton(
                onPressed: () => setSheet(() => f = f.copyWith(clearDates: true)),
                child: const Text('Ta bort datum'),
              ),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.of(c).pop(f), child: const Text('Visa')),
            TextButton(
              onPressed: () => Navigator.of(c)
                  .pop(f.copyWith(clearSupplier: true, clearCostType: true, clearDates: true)),
              child: const Text('Rensa filter'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// All unpaid invoices, whatever month: a card to open the list, or a calm
/// confirmation when there is nothing to pay.
class _UnpaidTile extends StatelessWidget {
  final List<Invoice> unpaid;
  const _UnpaidTile(this.unpaid);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final none = unpaid.isEmpty;
    final total = Money.sum(unpaid.map((i) => i.total));
    final late = unpaid.any((i) => (daysUntil(i.dueDate) ?? 1) < 0);
    final color = none ? AppTheme.seed : (late ? const Color(0xFFB3261E) : AppTheme.warning);
    return Card(
      margin: EdgeInsets.zero,
      color: none ? AppTheme.surface : (late ? const Color(0xFFFDECEA) : AppTheme.warningTint),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: none ? AppTheme.hairline : (late ? const Color(0xFFF5C6C2) : AppTheme.warningBorder)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UnpaidPage())),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            IconTile(none ? AppIcons.checkCircle : AppIcons.payments,
                background: color.withValues(alpha: 0.12), color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    none
                        ? 'Inga obetalda fakturor'
                        : 'Att betala: ${unpaid.length} ${unpaid.length == 1 ? 'faktura' : 'fakturor'}',
                    style: t.titleSmall?.copyWith(color: none ? null : color)),
                Text(none ? 'Allt är betalt' : (late ? 'Minst en har förfallit' : 'Tryck för att se och betala'),
                    style: t.bodySmall),
              ]),
            ),
            if (!none) Text(total.format(compact: true), style: t.titleSmall?.merge(moneyStyle).copyWith(color: color)),
            const SizedBox(width: 4),
            Icon(AppIcons.chevronRight, size: 18, color: AppTheme.muted),
          ]),
        ),
      ),
    );
  }
}
