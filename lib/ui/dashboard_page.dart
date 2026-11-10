import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../domain/comparison.dart';
import '../domain/dates.dart';
import '../domain/license.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/reports.dart';
import 'app_icons.dart';
import 'history_page.dart';
import 'record_details.dart';
import 'settings/activation_page.dart';
import 'theme.dart';
import 'unpaid_page.dart';
import 'widgets/charts.dart';
import 'widgets/common.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  static Future<YearReport> _year(AppController c, int y) async => const ReportGenerator().yearly(
        year: y,
        sales: await c.repo.dailySalesBetween('$y-01-01', '$y-12-31'),
        invoices: await c.repo.invoicesBetween('$y-01-01', '$y-12-31'),
        online: await c.repo.onlineSalesBetween('$y-01-01', '$y-12-31'),
      );

  @override
  Widget build(BuildContext context) {
    final ym = YearMonth.now();
    return Reloading<(MonthData, List<RegistrationSummary>, int, List<Invoice>, LicenseState, YearReport, YearReport)>(
      deps: ym.title,
      loader: (c) async => (
        await MonthData.load(c, ym),
        await c.repo.recentRegistrations(limit: 8),
        await c.repo.documentCount(fromIso: ym.firstDay, toIso: ym.lastDay),
        await c.repo.unpaidInvoices(),
        await c.repo.licenseState(),
        await _year(c, ym.year),
        await _year(c, ym.year - 1),
      ),
      builder: (context, data) {
        final (month, recent, count, unpaid, license, thisYear, lastYear) = data;
        final r = month.report;
        final t = Theme.of(context).textTheme;
        // The last six months, oldest first, across the turn of the year.
        final months = [
          for (var back = 5; back >= 0; back--)
            ym.month - back > 0
                ? (ym.month - back, thisYear.rows[ym.month - back - 1])
                : (ym.month - back + 12, lastYear.rows[ym.month - back + 11]),
        ];
        final previous = months[months.length - 2].$2;
        final categories = [
          for (final c in r.columns) (c.name, r.columnTotals[c.key] ?? Money.zero),
          if (!r.totalOnline.isZero) ('Online', r.totalOnline),
        ]..sort((a, b) => b.$2.ore.compareTo(a.$2.ore));
        final topCategory = categories.isEmpty ? Money.zero : categories.first.$2;
        final diff = r.vatDifference;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [
            if (license.status != LicenseStatus.active)
              Card(
                child: ListTile(
                  leading: const Icon(AppIcons.lock),
                  title: const Text('Appen behöver aktiveras'),
                  subtitle: Text(licenseStatusText(license)),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const ActivationPage())),
                ),
              ),
            if (unpaid.isNotEmpty) _UnpaidCard(unpaid),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _KeyFigure('Försäljning', r.totalAllSales, previous.sales, higherIsGood: true)),
              const SizedBox(width: 8),
              Expanded(child: _KeyFigure('Utgifter', r.totalExpenses, previous.expenses, higherIsGood: false)),
            ]),
            const SizedBox(height: 8),
            _Panel(
              title: 'Försäljning och utgifter, 6 månader',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                PairedBarChart(
                  labels: [for (final m in months) SwedishDates.shortMonths[m.$1 - 1]],
                  first: [for (final m in months) m.$2.sales.ore / 100],
                  second: [for (final m in months) m.$2.expenses.ore / 100],
                  semanticLabel: 'Försäljning och utgifter för de senaste sex månaderna',
                ),
                const SizedBox(height: 6),
                const Wrap(spacing: 14, children: [
                  LegendDot(AppTheme.seed, 'Försäljning'),
                  LegendDot(chartSecond, 'Utgifter'),
                ]),
              ]),
            ),
            if (categories.isNotEmpty)
              _Panel(
                title: 'Försäljning per kategori',
                child: _CategoryBars(categories: categories, top: topCategory),
              ),
            _Panel(
              child: Row(children: [
                const Icon(AppIcons.vat, color: AppTheme.seed),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(diff.isNegative ? 'Moms att få tillbaka (beräknad)' : 'Moms att betala (beräknad)',
                        style: t.bodySmall),
                    Text(diff.abs().format(), style: t.titleMedium?.merge(moneyStyle)),
                  ]),
                ),
                Text('$count dokument', style: t.bodySmall),
              ]),
            ),
            Text('Beräknad moms. Ersätter inte momsdeklarationen.', style: t.bodySmall),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: Text('Senaste registreringar', style: t.titleMedium)),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryPage())),
                  child: const Text('Visa historik'),
                ),
              ],
            ),
            if (recent.isEmpty)
              const EmptyState(icon: AppIcons.inbox, text: 'Inga registreringar ännu.')
            else
              for (final e in recent) RegistrationTile(entry: e),
          ],
        );
      },
    );
  }
}

/// The five largest categories, and all of them after "Visa alla".
class _CategoryBars extends StatefulWidget {
  static const shown = 5;
  final List<(String, Money)> categories;
  final Money top;
  const _CategoryBars({required this.categories, required this.top});

  @override
  State<_CategoryBars> createState() => _CategoryBarsState();
}

class _CategoryBarsState extends State<_CategoryBars> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final list = widget.categories;
    final more = list.length - _CategoryBars.shown;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final c in _all ? list : list.take(_CategoryBars.shown))
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(c.$1, style: t.bodyMedium)),
              Text(c.$2.format(compact: true), style: moneyStyle),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: widget.top.ore <= 0 ? 0 : (c.$2.ore / widget.top.ore).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: AppTheme.hairline,
                color: AppTheme.seed,
              ),
            ),
          ]),
        ),
      if (more > 0)
        TextButton.icon(
          onPressed: () => setState(() => _all = !_all),
          icon: Icon(_all ? AppIcons.collapse : AppIcons.expand),
          label: Text(_all ? 'Visa färre' : 'Visa alla ($more till)'),
        ),
    ]);
  }
}

/// A rounded white panel with an optional small title.
class _Panel extends StatelessWidget {
  final String? title;
  final Widget child;
  const _Panel({this.title, required this.child});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (title != null) ...[
              Text(title!, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
            ],
            child,
          ]),
        ),
      );
}

/// This month's figure and how it changed since last month.
class _KeyFigure extends StatelessWidget {
  final String label;
  final Money value;
  final Money previous;

  /// For sales a rise is good news; for expenses it is not.
  final bool higherIsGood;
  const _KeyFigure(this.label, this.value, this.previous, {required this.higherIsGood});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final change = CompareRow(0, value, previous).changePercent;
    final up = change != null && change > 0;
    final good = change == null || change == 0 || up == higherIsGood;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: t.bodySmall),
          const SizedBox(height: 2),
          FittedBox(child: Text(value.format(compact: true), style: t.titleLarge?.merge(moneyStyle))),
          const SizedBox(height: 2),
          if (change == null)
            Text('Ingen jämförelse', style: t.bodySmall)
          else
            Row(children: [
              Icon(up ? AppIcons.trendUp : AppIcons.trendDown,
                  size: 14, color: good ? AppTheme.seed : AppTheme.warning),
              const SizedBox(width: 4),
              Flexible(
                child: Text('${formatChange(change)} mot förra månaden',
                    style: t.bodySmall?.copyWith(color: good ? AppTheme.seed : AppTheme.warning)),
              ),
            ]),
        ]),
      ),
    );
  }
}

class RegistrationTile extends StatelessWidget {
  final RegistrationSummary entry;
  final bool showStatus;
  const RegistrationTile({super.key, required this.entry, this.showStatus = false});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final sub = [
      e.typeLabel,
      if (e.title.isNotEmpty) e.kind == 'z' ? 'Z-nr ${e.title}' : e.title,
      if (e.kind == 'invoice') 'Moms ${e.vat.format(compact: true)}',
      if (showStatus) e.confirmed ? 'Godkänd' : 'Ej godkänd',
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: IconTile(switch (e.kind) {
        'invoice' => AppIcons.expenses,
        'online' => AppIcons.delivery,
        _ => AppIcons.register,
      }),
      title: Text(SwedishDates.shortDay(e.date)),
      subtitle: Text(sub),
      trailing: Text(e.amount.format(compact: true), style: moneyStyle),
      onTap: () => openRecord(context, e.kind, e.id),
    );
  }
}

/// "Att betala": unpaid invoices, highlighted when one is due soon or late.
class _UnpaidCard extends StatelessWidget {
  final List<Invoice> unpaid;
  const _UnpaidCard(this.unpaid);

  @override
  Widget build(BuildContext context) {
    final total = Money.sum(unpaid.map((i) => i.total));
    final days = unpaid.map((i) => daysUntil(i.dueDate)).whereType<int>().toList()..sort();
    final first = days.isEmpty ? null : days.first;
    final urgent = first != null && first <= 3;
    final color = first != null && first < 0 ? Theme.of(context).colorScheme.error : AppTheme.warning;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: urgent ? color.withValues(alpha: 0.1) : null,
        child: ListTile(
          leading: Icon(AppIcons.payments, color: urgent ? color : null),
          title: Text('Att betala: ${unpaid.length} ${unpaid.length == 1 ? 'faktura' : 'fakturor'}'),
          subtitle: Text(first == null
              ? 'Inget förfallodatum angivet'
              : first < 0
                  ? 'Minst en faktura har förfallit'
                  : first == 0
                      ? 'En faktura förfaller i dag'
                      : 'Nästa förfaller om $first ${first == 1 ? 'dag' : 'dagar'}'),
          trailing: Text(total.format(compact: true), style: moneyStyle),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UnpaidPage())),
        ),
      ),
    );
  }
}
