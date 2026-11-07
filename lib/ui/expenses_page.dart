import 'package:flutter/material.dart';

import '../domain/cost_types.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'app_icons.dart';
import 'record_details.dart';
import 'theme.dart';
import 'unpaid_page.dart';
import 'widgets/common.dart';
import 'widgets/ledger_parts.dart';

/// Colours for expenses, matching the expenses bars on Översikt.
const _expense = Color(0xFFB4553A);
const _expenseTint = Color(0xFFFBE9E2);

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  YearMonth _ym = YearMonth.now();

  @override
  Widget build(BuildContext context) => Reloading<(MonthData, List<Invoice>)>(
        deps: _ym.title,
        loader: (c) async => (await MonthData.load(c, _ym), await c.repo.unpaidInvoices()),
        builder: (context, data) {
          final (m, unpaid) = data;
          final r = m.report;
          final byType = <String, Money>{};
          for (final i in m.invoices) {
            final label = CostType.labelFor(i.costType);
            byType[label] = (byType[label] ?? Money.zero) + (i.total - i.vatTotal);
          }
          final parts = byType.entries.map((e) => (e.key, e.value)).toList()
            ..sort((a, b) => b.$2.ore.compareTo(a.$2.ore));
          final invoices = [...m.invoices]..sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate));
          final unpaidThisMonth = m.invoices.where((i) => !i.paid).length;

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
              if (parts.isNotEmpty) ...[
                const SectionTitle('Per kostnadstyp', trailing: 'exkl. moms'),
                ShareBar(parts: parts, colors: costPalette),
              ],
              SectionTitle('Fakturor och kvitton', trailing: invoices.isEmpty ? null : '${invoices.length} st'),
              if (invoices.isEmpty)
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
                LedgerCard(children: [
                  for (final inv in invoices)
                    LedgerRow(
                      isoDate: inv.invoiceDate,
                      title: inv.supplier.isNotEmpty ? inv.supplier : (inv.total.isNegative ? 'Kreditnota' : 'Faktura'),
                      subtitle: [
                        if (CostType.byKey(inv.costType) != null) CostType.labelFor(inv.costType),
                        if (inv.invoiceNumber.isNotEmpty) 'Nr ${inv.invoiceNumber}',
                        'Moms ${inv.vatTotal.format(compact: true)}',
                      ].join(' · '),
                      amount: inv.total,
                      badgeBackground: _expenseTint,
                      badgeColor: _expense,
                      chips: [
                        if (inv.total.isNegative)
                          const StatusChip('Kreditnota', color: AppTheme.seed, background: AppTheme.tint),
                        if (!inv.paid) _dueChip(inv),
                      ],
                      onTap: () => openRecord(context, 'invoice', inv.id!),
                    ),
                ]),
            ],
          );
        },
      );

  Widget _dueChip(Invoice inv) {
    final days = daysUntil(inv.dueDate);
    if (days == null) return const StatusChip('Obetald');
    if (days < 0) return const StatusChip('Förfallen', color: Color(0xFFB3261E), background: Color(0xFFFDECEA));
    if (days == 0) return const StatusChip('Förfaller i dag');
    return StatusChip('Obetald · $days d kvar');
  }
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
      color: none ? Colors.white : (late ? const Color(0xFFFDECEA) : AppTheme.warningTint),
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
            const Icon(AppIcons.chevronRight, size: 18, color: AppTheme.muted),
          ]),
        ),
      ),
    );
  }
}
