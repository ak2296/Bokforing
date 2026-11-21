import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../data/bank_match_store.dart';
import '../domain/cash_summary.dart';
import '../domain/closed_days.dart';
import '../domain/dates.dart';
import '../domain/money.dart';
import 'app_icons.dart';
import 'bank_match_page.dart';
import 'record_details.dart';
import 'scan/scan_flow.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/ledger_parts.dart';
import 'widgets/blur_overlay.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  YearMonth _ym = YearMonth.now();

  @override
  Widget build(BuildContext context) => Reloading<(MonthData, ClosedDays, BankMatchFlags)>(
        deps: _ym.title,
        loader: (c) async => (await MonthData.load(c, _ym), await c.repo.closedDays(), await loadBankMatch(c.repo)),
        builder: (context, data) {
          final (m, closed, flags) = data;
          final cash = CashSummary.of(m.sales, m.invoices);
          final r = m.report;
          final coverage = ZCoverage.of(
            year: _ym.year,
            month: _ym.month,
            today: DateTime.now(),
            scannedDates: {for (final d in m.sales) d.businessDate},
            closed: closed,
          );
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
                  badgeBackground: AppTheme.salesTint,
                  badgeColor: AppTheme.sales,
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
                    if (o.documentNumber.isNotEmpty) 'Nr ${o.documentNumber}',
                    'Moms ${o.vat.format(compact: true)}',
                  ].join(' · '),
                  amount: o.amount,
                  chips: [StatusChip('Online', color: AppTheme.onlineChipText, background: AppTheme.onlineChip)],
                  amountColor: AppTheme.onlineAmount,
                  // The same blue date badge as a Z-report; the chip and the amount set it apart.
                  badgeBackground: AppTheme.salesTint,
                  badgeColor: AppTheme.sales,
                  onTap: () => openRecord(context, 'online', o.id!),
                ),
              ),
          ]..sort((a, b) => b.$1.compareTo(a.$1));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 112),
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
                color: AppTheme.sales,
                stats: [
                  ('Utgående moms', r.totalOutputVat.format(compact: true)),
                  ('Z-rapporter', coverage.text),
                  ('Online', r.totalOnline.format(compact: true)),
                ],
                extraStats: [
                  HeroStat('Kontant', cash.cashIn.format(compact: true)),
                  HeroStat('Kort och Swish', cash.cardIn.format(compact: true)),
                  HeroStat('Z mot bank', flags.zText(m.sales),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BankMatchPage(invoices: false)))),
                ],
              ),
              if (coverage.missing.isNotEmpty) ...[
                const SizedBox(height: 10),
                _Notice(
                  coverage.missing.length == 1
                      ? 'Z-rapport saknas för ${SwedishDates.mediumDay(coverage.missing.first)}.'
                      : 'Z-rapport saknas för ${coverage.missing.length} dagar.',
                  onTap: () => showMissingZ(context, coverage.missing),
                ),
              ],
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
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.sales,
                  side: BorderSide(color: AppTheme.sales, width: 1.5),
                ),
                icon: const Icon(AppIcons.file, size: 18),
                label: const Text('Matcha Z-rapporter mot bankfil'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BankMatchPage(invoices: false))),
              ),
              SectionTitle('Dagar', trailing: entries.isEmpty ? null : '${entries.length} st'),
              if (entries.isEmpty)
                const _Empty(icon: AppIcons.register, text: 'Inga Z-rapporter eller onlineförsäljning den här månaden.')
              else
                ...weekCards(entries, color: AppTheme.sales),
            ],
          );
        },
      );
}

class _Notice extends StatelessWidget {
  final String text;

  /// When set the whole card is tappable (it opens a box to choose in).
  final VoidCallback? onTap;
  const _Notice(this.text, {this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: AppTheme.warningTint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppTheme.warningBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(AppIcons.warning, size: 18, color: AppTheme.warning),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(color: AppTheme.warning, fontSize: 13))),
              if (onTap != null) Icon(AppIcons.chevronRight, size: 18, color: AppTheme.warning),
            ]),
          ),
        ),
      );
}

/// The box that opens from the alert: for the oldest day without a Z-report the
/// owner chooses to scan it or to say the shop was closed that day. The x in the
/// corner closes it without changing anything.
Future<void> showMissingZ(BuildContext context, List<String> missing) async {
  final controller = AppScope.read(context);
  final days = [...missing];
  while (days.isNotEmpty && context.mounted) {
    final day = days.first;
    final d = SwedishDates.parseIso(day);
    const names = ['måndag', 'tisdag', 'onsdag', 'torsdag', 'fredag', 'lördag', 'söndag'];
    if (!context.mounted) return;
    final choice = await showBlurDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 8, 8, 0),
        title: Row(children: [
          const Expanded(child: Text('Z-rapport saknas')),
          IconButton(
            tooltip: 'Stäng',
            icon: const Icon(AppIcons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${d == null ? day : '${names[d.weekday - 1]} ${SwedishDates.mediumDay(day)}'}'
              '${days.length > 1 ? ' (och ${days.length - 1} dagar till)' : ''}'),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(AppIcons.scan),
              label: const Text('Skanna Z-rapporten'),
              onPressed: () => Navigator.pop(context, 'scan'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(AppIcons.checkCircle),
              label: const Text('Butiken var stängd'),
              onPressed: () => Navigator.pop(context, 'closed'),
            ),
          ),
        ]),
      ),
    );
    if (choice == 'scan') {
      if (context.mounted) await startScan(context);
      return;
    }
    if (choice != 'closed') return; // x: nothing changes
    await controller.repo.saveClosedDays((await controller.repo.closedDays()).withDate(day));
    controller.dataChanged();
    days.removeAt(0);
  }
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
