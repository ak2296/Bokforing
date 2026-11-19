import 'package:flutter/material.dart';

import 'package:open_filex/open_filex.dart' show ResultType;

import '../app/app_controller.dart';
import '../app/app_update.dart';
import '../domain/comparison.dart';
import '../domain/dates.dart';
import '../domain/license.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/reports.dart';
import 'app_icons.dart';
import 'history_page.dart';
import 'incomplete_page.dart';
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
    return Reloading<(MonthData, List<RegistrationSummary>, int, List<Invoice>, LicenseState, YearReport, YearReport, DashboardExtras, MonthData)>(
      deps: ym.title,
      loader: (c) async => (
        await MonthData.load(c, ym),
        await c.repo.recentRegistrations(limit: 5),
        await c.repo.documentCount(fromIso: ym.firstDay, toIso: ym.lastDay),
        await c.repo.unpaidInvoices(),
        await c.repo.licenseState(),
        await _year(c, ym.year),
        await _year(c, ym.year - 1),
        await DashboardExtras.load(c),
        // Last month up to the same day, so the hero compares like with like.
        await MonthData.load(c, ym.previous, upToDay: DateTime.now().day),
      ),
      builder: (context, data) {
        final (month, recent, count, unpaid, license, thisYear, lastYear, extras, previousToDate) = data;
        final r = month.report;
        final t = Theme.of(context).textTheme;
        // The last six months, oldest first, across the turn of the year.
        final months = [
          for (var back = 5; back >= 0; back--)
            ym.month - back > 0
                ? (ym.month - back, thisYear.rows[ym.month - back - 1])
                : (ym.month - back + 12, lastYear.rows[ym.month - back + 11]),
        ];
        final diff = r.vatDifference;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 112),
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
            const _UpdateCard(),
            _RakningarPill(unpaid),
            _MonthHero(report: r, previous: previousToDate.report, title: ym.title),
            const SizedBox(height: 8),
            _Panel(
              child: Row(children: [
                Icon(AppIcons.vat, color: AppTheme.seed),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(diff.isNegative ? 'Moms att få tillbaka i ${SwedishDates.months[ym.month - 1]} (beräknad)' : 'Moms att betala i ${SwedishDates.months[ym.month - 1]} (beräknad)',
                        style: t.bodySmall),
                    Text(diff.abs().format(), style: t.titleMedium?.merge(moneyStyle)),
                  ]),
                ),
                Text('$count dokument', style: t.bodySmall),
              ]),
            ),
            _TrendPanel(months: months, weekdays: extras.weekdayAverages),
            Text('Beräknad moms. Ersätter inte momsdeklarationen.', style: t.bodySmall),
            if (month.invoices.any((i) => i.isIncomplete)) ...[
              const SizedBox(height: 8),
              IncompleteNotice(
                  count: month.invoices.where((i) => i.isIncomplete).length,
                  from: ym.firstDay,
                  to: ym.lastDay,
                  period: ym.title),
            ],
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Senaste registreringar', style: t.titleMedium),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryPage())),
                child: const Text('Visa alla'),
              ),
            ]),
            if (recent.isEmpty)
              const EmptyState(icon: AppIcons.inbox, text: 'Börja med att skanna ditt första dokument: tryck på Skanna längst ner.')
            else
              Card(
                margin: EdgeInsets.zero,
                child: Column(children: [
                  for (final (i, e) in recent.indexed) ...[
                    if (i > 0) Divider(height: 1, indent: 64, color: AppTheme.hairline),
                    _RecentRow(e),
                  ],
                ]),
              ),
          ],
        );
      },
    );
  }
}

/// A rounded panel for a chart or a figure.
class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: child,
        ),
      );
}

/// This month's figure and how it changed since last month.
/// A newer version exists: download it and hand it to Android's installer.
/// The old app is replaced and all data stays.
class _UpdateCard extends StatefulWidget {
  const _UpdateCard();

  @override
  State<_UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<_UpdateCard> {
  double? _progress;
  String? _problem;

  Future<void> _install(UpdateInfo info) async {
    setState(() {
      _progress = 0;
      _problem = null;
    });
    try {
      final file = await AppUpdater.download(info, (got, total) {
        if (mounted && total > 0) setState(() => _progress = got / total);
      });
      final r = await AppUpdater.install(file);
      if (mounted) {
        setState(() {
          _progress = null;
          if (r.type != ResultType.done) {
            _problem = 'Android släppte inte igenom installationen. Tillåt att Quee installerar appar i telefonens inställningar och försök igen.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _problem = 'Hämtningen misslyckades: ${AppUpdater.failureReason(e)}. Försök igen.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.read(context);
    return ValueListenableBuilder<UpdateInfo?>(
      valueListenable: controller.updateAvailable,
      builder: (context, info, _) {
        if (info == null) return const SizedBox.shrink();
        final t = Theme.of(context).textTheme;
        final mb = info.size > 0 ? ', ${(info.size / 1048576).round()} MB' : '';
        return Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 12),
          child: Card(
            margin: EdgeInsets.zero,
            color: AppTheme.tint,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppTheme.seed)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(AppIcons.download, color: AppTheme.seed),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Ny version finns', style: t.titleSmall)),
                ]),
                const SizedBox(height: 4),
                Text('${info.name}$mb. Dina uppgifter finns kvar.', style: t.bodySmall),
                if (_progress != null) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 4),
                  Text('Hämtar … ${(_progress! * 100).round()} %', style: t.bodySmall),
                ] else ...[
                  const SizedBox(height: 10),
                  FilledButton(onPressed: () => _install(info), child: const Text('Hämta och installera')),
                  const SizedBox(height: 6),
                  Text('Första gången frågar Android om Quee får installera appar.', style: t.bodySmall),
                ],
                if (_problem != null) ...[
                  const SizedBox(height: 6),
                  Text(_problem!, style: t.bodySmall?.copyWith(color: AppTheme.danger)),
                ],
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// "Räkningar": what is left to pay, as a pill under the settings icon with the
/// number of unpaid invoices as a badge. Gone when nothing is unpaid; red when
/// an invoice is overdue, yellow otherwise.
class _RakningarPill extends StatelessWidget {
  final List<Invoice> unpaid;
  const _RakningarPill(this.unpaid);

  @override
  Widget build(BuildContext context) {
    if (unpaid.isEmpty) return const SizedBox.shrink();
    final late = unpaid.any((i) => (daysUntil(i.dueDate) ?? 0) < 0);
    final fill = late ? AppTheme.dangerTint : AppTheme.warningTint;
    final border = late ? AppTheme.dangerBorder : AppTheme.warningBorder;
    final text = late ? AppTheme.danger : AppTheme.warning;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerRight,
        child: Semantics(
          button: true,
          label: 'Räkningar, ${unpaid.length} obetalda${late ? ', en eller flera har förfallit' : ''}',
          child: Material(
            color: fill,
            shape: StadiumBorder(side: BorderSide(color: border)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UnpaidPage())),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('Räkningar', style: t.labelLarge?.copyWith(color: text, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Container(
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: text, borderRadius: BorderRadius.circular(12)),
                    child: Text('${unpaid.length}',
                        style: t.labelMedium?.copyWith(color: AppTheme.background, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The month at a glance: the result before tax (without moms, as in the
/// report) and, under it, sales and expenses with the change since last month.
class _MonthHero extends StatelessWidget {
  final MonthlyReport report;
  final MonthlyReport previous;
  final String title;
  const _MonthHero({required this.report, required this.previous, required this.title});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = report;
    final result = (r.totalAllSales - r.totalOutputVat) - (r.totalExpenses - r.totalInputVat);
    const white = Colors.white;
    final soft = Colors.white.withValues(alpha: 0.78);
    final dark = AppTheme.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark ? const [Color(0xFF2A8F6D), Color(0xFF1B6650)] : const [Color(0xFF0B6B4E), Color(0xFF084D38)],
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Resultat före skatt, $title', style: t.bodySmall?.copyWith(color: soft)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(result.format(compact: true),
                style: t.headlineMedium?.merge(moneyStyle).copyWith(color: white, fontWeight: FontWeight.w600)),
          ),
          Text('Exkl. moms', style: t.bodySmall?.copyWith(color: soft)),
          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.25)),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _HeroFigure('Försäljning', r.totalAllSales, previous.totalAllSales, higherIsGood: true)),
            const SizedBox(width: 12),
            Expanded(child: _HeroFigure('Utgifter', r.totalExpenses, previous.totalExpenses, higherIsGood: false)),
          ]),
        ]),
      ),
    );
  }
}

class _HeroFigure extends StatelessWidget {
  final String label;
  final Money value;
  final Money previous;

  /// For sales a rise is good news; for expenses it is not.
  final bool higherIsGood;
  const _HeroFigure(this.label, this.value, this.previous, {required this.higherIsGood});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final change = CompareRow(0, value, previous).changePercent;
    final up = change != null && change > 0;
    final good = change == null || change == 0 || up == higherIsGood;
    final soft = Colors.white.withValues(alpha: 0.78);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: t.bodySmall?.copyWith(color: soft)),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(value.format(compact: true),
            style: t.titleMedium?.merge(moneyStyle).copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      if (change == null)
        Text('Ingen jämförelse', style: t.bodySmall?.copyWith(color: soft))
      else
        Row(children: [
          Icon(up ? AppIcons.trendUp : AppIcons.trendDown,
              size: 14, color: good ? Colors.white : const Color(0xFFFFC98F)),
          const SizedBox(width: 4),
          Flexible(
            child: Text('${formatChange(change)} mot förra mån.',
                style: t.bodySmall?.copyWith(color: good ? soft : const Color(0xFFFFC98F)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ]),
    ]);
  }
}

/// Six months of sales and expenses, or the weekday averages, one card with a
/// switch. Months before the first with any figure are left out (at least three
/// stay), so the bars use the width.
class _TrendPanel extends StatefulWidget {
  final List<(int, YearRow)> months;
  final List<double> weekdays;
  const _TrendPanel({required this.months, required this.weekdays});

  @override
  State<_TrendPanel> createState() => _TrendPanelState();
}

class _TrendPanelState extends State<_TrendPanel> {
  bool _weekdays = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    var months = widget.months;
    final firstUsed = months.indexWhere((m) => m.$2.sales.ore != 0 || m.$2.expenses.ore != 0);
    if (firstUsed > 0) months = months.sublist(firstUsed.clamp(0, months.length - 5));
    return _Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(_weekdays ? 'Snitt försäljning per veckodag (kr), senaste 12 veckorna' : 'Försäljning och utgifter', style: t.bodySmall)),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: false, label: Text('Månader')),
              ButtonSegment(value: true, label: Text('Veckodag')),
            ],
            selected: {_weekdays},
            onSelectionChanged: (v) => setState(() => _weekdays = v.first),
          ),
        ]),
        const SizedBox(height: 10),
        if (_weekdays)
          _Weekdays(widget.weekdays)
        else ...[
          PairedBarChart(
            labels: [for (final m in months) SwedishDates.shortMonths[m.$1 - 1]],
            first: [for (final m in months) m.$2.sales.ore / 100],
            second: [for (final m in months) m.$2.expenses.ore / 100],
            semanticLabel: 'Försäljning och utgifter för de senaste månaderna',
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 14, children: [
            LegendDot(AppTheme.seed, 'Försäljning'),
            LegendDot(chartSecond, 'Utgifter'),
          ]),
        ],
      ]),
    );
  }
}

/// One line in the latest registrations: what it is, when, and the amount.
class _RecentRow extends StatelessWidget {
  final RegistrationSummary entry;
  const _RecentRow(this.entry);

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final title = e.title.isEmpty ? e.typeLabel : (e.kind == 'z' ? 'Z-rapport ${e.title}' : e.title);
    return ListTile(
      leading: IconTile(switch (e.kind) {
        'invoice' => AppIcons.expenses,
        'online' => AppIcons.delivery,
        'payslip' => AppIcons.payments,
        _ => AppIcons.register,
      }),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${SwedishDates.shortDay(e.date)} · ${e.typeLabel}'),
      trailing: Text(e.amount.format(compact: true), style: moneyStyle),
      onTap: () => openRecord(context, e.kind, e.id),
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
