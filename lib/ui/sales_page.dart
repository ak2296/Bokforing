import 'package:flutter/material.dart';

import '../domain/money.dart';
import 'app_icons.dart';
import 'record_details.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/ledger_parts.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  YearMonth _ym = YearMonth.now();

  @override
  Widget build(BuildContext context) => Reloading<MonthData>(
        deps: _ym.title,
        loader: (c) => MonthData.load(c, _ym),
        builder: (context, m) {
          final r = m.report;
          final categories = [
            for (final c in r.columns) (c.name, r.columnTotals[c.key] ?? Money.zero),
            if (!r.totalOnline.isZero) ('Online', r.totalOnline),
          ]..sort((a, b) => b.$2.ore.compareTo(a.$2.ore));
          final withDifference = m.sales.where((d) => d.hasDifference).length;
          // Z-reports and online payouts together, newest first.
          final entries = <(String, Widget)>[
            for (final d in m.sales)
              (
                d.businessDate,
                LedgerRow(
                  isoDate: d.businessDate,
                  title: (d.zNumber ?? '').isEmpty ? 'Z-rapport' : 'Z-rapport ${d.zNumber}',
                  subtitle: 'Moms ${d.outputVat.format(compact: true)}',
                  amount: d.detailedTotal,
                  chips: [if (d.hasDifference) StatusChip('Skillnad ${d.difference.format(compact: true)}')],
                  onTap: () => openRecord(context, 'z', d.id!),
                ),
              ),
            for (final o in m.online)
              (
                o.paymentDate,
                LedgerRow(
                  isoDate: o.paymentDate,
                  title: o.partner.isEmpty ? 'Onlineförsäljning' : o.partner,
                  subtitle: [
                    'Online',
                    if (o.documentNumber.isNotEmpty) 'Nr ${o.documentNumber}',
                    if (!o.vat.isZero) 'Moms ${o.vat.format(compact: true)}',
                  ].join(' · '),
                  amount: o.amount,
                  badgeBackground: AppTheme.onlineTint,
                  badgeColor: AppTheme.online,
                  onTap: () => openRecord(context, 'online', o.id!),
                ),
              ),
          ]..sort((a, b) => b.$1.compareTo(a.$1));

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
                label: 'Försäljning',
                total: r.totalAllSales,
                icon: AppIcons.register,
                color: AppTheme.seed,
                stats: [
                  ('Utgående moms', r.totalOutputVat.format(compact: true)),
                  ('Z-rapporter', '${m.sales.length}'),
                  ('Online', r.totalOnline.format(compact: true)),
                ],
              ),
              if (withDifference > 0) ...[
                const SizedBox(height: 10),
                _Notice(
                  '$withDifference ${withDifference == 1 ? 'Z-rapport har' : 'Z-rapporter har'} skillnad mellan '
                  'raderna och totalen. Öppna och kontrollera.',
                ),
              ],
              if (categories.any((c) => c.$2.ore > 0)) ...[
                const SectionTitle('Per kategori'),
                ShareBar(parts: categories, colors: salesPalette),
              ],
              SectionTitle('Dagar', trailing: entries.isEmpty ? null : '${entries.length} st'),
              if (entries.isEmpty)
                const _Empty(icon: AppIcons.register, text: 'Inga Z-rapporter eller onlineförsäljning den här månaden.')
              else
                LedgerCard(children: [for (final e in entries) e.$2]),
            ],
          );
        },
      );
}

class _Notice extends StatelessWidget {
  final String text;
  const _Notice(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.warningTint,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.warningBorder),
        ),
        child: Row(children: [
          const Icon(AppIcons.warning, size: 18, color: AppTheme.warning),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: AppTheme.warning, fontSize: 13))),
        ]),
      );
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Empty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          child: Column(children: [
            IconTile(icon),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
}
