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
        invoices: await c.repo.invoicesForReports('$y-01-01', '$y-12-31'),
        online: await c.repo.onlineSalesBetween('$y-01-01', '$y-12-31'),
      );

  @override
  Widget build(BuildContext context) {
    final ym = YearMonth.now();
    return Reloading<(MonthData, List<RegistrationSummary>, int, List<Invoice>, LicenseState, YearReport, YearReport, DashboardExtras)>(
      deps: ym.title,
      loader: (c) async => (
        await MonthData.load(c, ym),
        await c.repo.recentRegistrations(limit: 8),
        await c.repo.documentCount(fromIso: ym.firstDay, toIso: ym.lastDay),
        await c.repo.unpaidInvoices(),
        await c.repo.licenseState(),
        await _year(c, ym.year),
        await _year(c, ym.year - 1),
        await DashboardExtras.load(c),
      ),
      builder: (context, data) {
        final (month, recent, count, unpaid, license, thisYear, lastYear, extras) = data;
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
                Wrap(spacing: 14, children: [
                  LegendDot(AppTheme.seed, 'Försäljning'),
                  LegendDot(chartSecond, 'Utgifter'),
                ]),
              ]),
            ),
            _Panel(title: 'Veckodagar, snitt senaste 12 veckorna', child: _Weekdays(extras.weekdayAverages)),
            if (extras.upcoming.isNotEmpty) _Panel(title: 'Kommande betalningar', child: _Upcoming(extras.upcoming)),
            _Panel(
              child: Row(children: [
                Icon(AppIcons.vat, color: AppTheme.seed),
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
        'payslip' => AppIcons.payments,
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

/// What the overview panels need beyond the month's report.
class DashboardExtras {
  /// Average sales per weekday (Monday first) over the last 12 weeks, in kr.
  final List<double> weekdayAverages;

  /// Unpaid invoices with a due date, soonest first.
  final List<Invoice> upcoming;
  const DashboardExtras(this.weekdayAverages, this.upcoming);

  static Future<DashboardExtras> load(AppController c, {DateTime? now}) async {
    final today = now ?? DateTime.now();
    final from = today.subtract(const Duration(days: 12 * 7 - 1));
    final recent = await c.repo.dailySalesBetween(SwedishDates.iso(from), SwedishDates.iso(today));
    final unpaid = [for (final i in await c.repo.unpaidInvoices()) if (i.dueDate != null) i]
      ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    return DashboardExtras(weekdayAverage(recent), unpaid);
  }

  /// Average of the days that have a Z-report, for each weekday.
  static List<double> weekdayAverage(List<DailySales> days) {
    final sums = List<double>.filled(7, 0), counts = List<int>.filled(7, 0);
    for (final d in days) {
      final date = SwedishDates.parseIso(d.businessDate);
      if (date == null) continue;
      sums[date.weekday - 1] += d.detailedTotal.ore / 100;
      counts[date.weekday - 1]++;
    }
    return [for (var i = 0; i < 7; i++) counts[i] == 0 ? 0 : sums[i] / counts[i]];
  }
}

/// Seven bars, Monday to Sunday, the strongest day in pumpkin.
class _Weekdays extends StatelessWidget {
  final List<double> averages;
  const _Weekdays(this.averages);

  static const _names = ['mån', 'tis', 'ons', 'tor', 'fre', 'lör', 'sön'];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final top = averages.fold<double>(0, (a, b) => b > a ? b : a);
    if (top <= 0) return Text('Ingen försäljning registrerad de senaste veckorna.', style: t.bodySmall);
    final best = averages.indexOf(top);
    return Semantics(
      label: 'Snittförsäljning per veckodag, högst på ${_names[best]}',
      child: SizedBox(
        height: 110,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(averages[i] <= 0 ? '' : Money(averages[i].round() * 100).format(unit: false, compact: true),
                      maxLines: 1, style: t.bodySmall?.copyWith(fontSize: 9.5)),
                  const SizedBox(height: 2),
                  Container(
                    height: 4 + 64 * (averages[i] / top),
                    decoration: BoxDecoration(
                      color: i == best ? AppTheme.pumpkin : AppTheme.seed,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_names[i], style: t.bodySmall),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

/// The next unpaid invoices by due date.
class _Upcoming extends StatelessWidget {
  final List<Invoice> invoices;
  const _Upcoming(this.invoices);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(children: [
      for (final i in invoices.take(4))
        InkWell(
          onTap: () => openRecord(context, 'invoice', i.id!),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.supplier.isEmpty ? 'Faktura' : i.supplier,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                  Text(_when(i.dueDate),
                      style: t.bodySmall?.copyWith(color: (daysUntil(i.dueDate) ?? 1) < 0 ? AppTheme.warning : null)),
                ]),
              ),
              Text(i.total.format(compact: true), style: t.titleSmall?.merge(moneyStyle)),
            ]),
          ),
        ),
      if (invoices.length > 4)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UnpaidPage())),
            child: Text('Visa alla (${invoices.length})'),
          ),
        ),
    ]);
  }

  static String _when(String? due) {
    final d = daysUntil(due);
    if (d == null || due == null) return '';
    final text = SwedishDates.shortDay(due);
    return d < 0 ? 'Förföll $text' : d == 0 ? 'Förfaller i dag' : 'Förfaller $text (om $d d)';
  }
}
