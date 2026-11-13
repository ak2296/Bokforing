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
import 'incomplete_page.dart';
import 'record_details.dart';
import 'settings/activation_page.dart';
import 'settings/backup_page.dart';
import 'theme.dart';
import 'unpaid_page.dart';
import 'widgets/charts.dart';
import 'widgets/common.dart';
import 'widgets/unpaid_level.dart';

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
        await c.repo.recentRegistrations(limit: 5),
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
            _TopCards(unpaid),
            const SizedBox(height: 8),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _KeyFigure('Försäljning', r.totalAllSales, previous.sales, higherIsGood: true)),
                const SizedBox(width: 8),
                Expanded(child: _KeyFigure('Utgifter', r.totalExpenses, previous.expenses, higherIsGood: false)),
              ]),
            ),
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
            if (month.invoices.any((i) => i.isIncomplete)) ...[
              const SizedBox(height: 8),
              IncompleteNotice(
                  count: month.invoices.where((i) => i.isIncomplete).length,
                  from: ym.firstDay,
                  to: ym.lastDay,
                  period: ym.title),
            ],
            const SizedBox(height: 20),
            Text('Senaste registreringar', style: t.titleMedium),
            const SizedBox(height: 4),
            if (recent.isEmpty)
              const EmptyState(icon: AppIcons.inbox, text: 'Börja med att skanna ditt första dokument: tryck på Skanna längst ner.')
            else
              for (final e in recent) RegistrationTile(entry: e),
            if (license.license?.until != null) _ActivationLine(license.license!.until!),
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
    } catch (_) {
      if (mounted) {
        setState(() {
          _progress = null;
          _problem = 'Hämtningen misslyckades. Kontrollera nätverket och försök igen.';
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
          padding: const EdgeInsets.only(top: 12),
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

/// Two half-width cards at the top: the backup and what is left to pay.
class _TopCards extends StatefulWidget {
  final List<Invoice> unpaid;
  const _TopCards(this.unpaid);

  @override
  State<_TopCards> createState() => _TopCardsState();
}

class _TopCardsState extends State<_TopCards> {
  bool? _on;
  DateTime? _last;
  int? _reminderDays;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final c = AppScope.read(context);
    final on = await c.autoBackup?.active() ?? false;
    final last = await c.autoBackup?.last();
    final days = await reminderWindow(c.repo);
    if (mounted) {
      setState(() {
        _on = on;
        _last = last;
        _reminderDays = days;
      });
    }
  }

  Widget _card({required Color fill, required Color border, required VoidCallback onTap, required Widget child}) => Card(
        margin: EdgeInsets.zero,
        color: fill,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(12), child: child)),
      );

  @override
  Widget build(BuildContext context) {
    final on = _on;
    if (on == null) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final info = UnpaidInfo.of(widget.unpaid, _reminderDays);
    final colors = unpaidColors(info.level);
    final upcoming = [
      for (final i in widget.unpaid)
        if (i.dueDate != null && (daysUntil(i.dueDate) ?? -1) >= 0) i
    ]..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    final next = upcoming.firstOrNull;
    final last = _last == null
        ? 'Ingen'
        : '${SwedishDates.iso(_last!)} ${_last!.hour.toString().padLeft(2, '0')}:${_last!.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: _card(
              fill: on ? AppTheme.surface : AppTheme.warningTint,
              border: on ? AppTheme.hairline : AppTheme.warningBorder,
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BackupPage()));
                _load();
              },
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Säkerhetskopia', style: t.titleSmall?.copyWith(color: on ? null : AppTheme.warning)),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(on ? AppIcons.checkCircle : AppIcons.crossCircle,
                      size: 16, color: on ? AppTheme.seed : AppTheme.danger),
                  const SizedBox(width: 5),
                  Text(on ? 'Automatisk' : 'Av', style: t.bodySmall),
                ]),
                const SizedBox(height: 4),
                Text('Senaste kopia', style: t.bodySmall),
                Text(last, style: t.bodySmall?.copyWith(color: AppTheme.ink)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _card(
              fill: colors.fill,
              border: colors.border,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UnpaidPage())),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Att betala', style: t.titleSmall?.copyWith(color: colors.text)),
                const SizedBox(height: 4),
                Text('${info.count} ${info.count == 1 ? 'faktura' : 'fakturor'}', style: t.bodySmall),
                Text(info.total.format(compact: true), style: t.titleMedium?.merge(moneyStyle).copyWith(color: colors.text)),
                Text('Förfallit: ${info.overdue}',
                    style: t.bodySmall?.copyWith(color: info.overdue > 0 ? AppTheme.danger : null)),
                if (next != null)
                  Text('Nästa: ${SwedishDates.shortDay(next.dueDate!)}, ${next.total.format(compact: true)}',
                      style: t.bodySmall?.copyWith(color: AppTheme.ink, fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// When the activation ends. Red the last 10 days.
class _ActivationLine extends StatelessWidget {
  final String until;
  const _ActivationLine(this.until);

  @override
  Widget build(BuildContext context) {
    final days = daysUntil(until);
    final soon = days != null && days <= 10;
    final text = days == null
        ? 'Aktiverad till $until'
        : days < 0
            ? 'Aktiveringen tog slut $until'
            : soon
                ? 'Aktiverad till $until (om $days d)'
                : 'Aktiverad till $until';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(children: [
        const Divider(),
        const SizedBox(height: 10),
        Text(text,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: soon ? AppTheme.danger : AppTheme.seed, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

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
