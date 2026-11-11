import 'package:flutter/material.dart';

import '../app_icons.dart';

import '../../app/app_controller.dart';
import '../../app/settings_keys.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../domain/reports.dart';

/// Year + month, with navigation helpers.
class YearMonth {
  final int year;
  final int month;
  const YearMonth(this.year, this.month);

  factory YearMonth.now() {
    final n = DateTime.now();
    return YearMonth(n.year, n.month);
  }

  YearMonth get previous => month == 1 ? YearMonth(year - 1, 12) : YearMonth(year, month - 1);
  YearMonth get next => month == 12 ? YearMonth(year + 1, 1) : YearMonth(year, month + 1);
  String get firstDay => '${SwedishDates.monthKey(year, month)}-01';
  String get lastDay => '${SwedishDates.monthKey(year, month)}-31';
  String get title => SwedishDates.monthTitle(year, month);
}

class MonthData {
  final BusinessProfile profile;
  final List<Category> categories;
  final List<DailySales> sales;
  final List<Invoice> invoices;
  final List<OnlineSale> online;
  final MonthlyReport report;

  /// "Avrunda utgifter" is on: [report] adds up whole kronor. [invoices] stay
  /// exact, so what is missing on an invoice is judged on the real amounts.
  final bool rounded;

  /// The month's lönebesked (by payout date). They are in [report] as
  /// expenses, but not in [invoices].
  final List<Payslip> payslips;
  const MonthData(this.profile, this.categories, this.sales, this.invoices, this.online, this.report,
      {this.rounded = false, this.payslips = const []});

  static Future<MonthData> load(AppController c, YearMonth ym) async {
    final repo = c.repo;
    final profile = await repo.profile();
    final cats = await repo.categories(includeInactive: true);
    final sales = await repo.dailySalesBetween(ym.firstDay, ym.lastDay);
    final invoices = await repo.invoicesBetween(ym.firstDay, ym.lastDay);
    final online = await repo.onlineSalesBetween(ym.firstDay, ym.lastDay);
    final rounded = await repo.boolSetting(SettingsKeys.roundExpenses);
    final payslips = await repo.payslipsBetween(ym.firstDay, ym.lastDay);
    final expenses = [
      ...invoices,
      for (final p in payslips) ...p.asExpenses(),
    ];
    final report = const ReportGenerator().monthly(
        year: ym.year,
        month: ym.month,
        categories: cats,
        sales: sales,
        invoices: rounded ? [for (final i in expenses) i.roundedToKr()] : expenses,
        online: online);
    return MonthData(profile, cats, sales, invoices, online, report, rounded: rounded, payslips: payslips);
  }
}

class MonthSwitcher extends StatelessWidget {
  final YearMonth value;
  final ValueChanged<YearMonth> onChanged;
  const MonthSwitcher({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
              tooltip: 'Föregående månad',
              icon: const Icon(AppIcons.chevronLeft),
              onPressed: () => onChanged(value.previous)),
          Text(value.title, style: Theme.of(context).textTheme.titleMedium),
          IconButton(
              tooltip: 'Nästa månad',
              icon: const Icon(AppIcons.chevronRight),
              onPressed: () => onChanged(value.next)),
        ],
      );
}

/// Reloads [loader] whenever app data changes or [deps] change.
class Reloading<T> extends StatefulWidget {
  final Future<T> Function(AppController c) loader;
  final Widget Function(BuildContext context, T data) builder;
  final Object? deps;
  const Reloading({super.key, required this.loader, required this.builder, this.deps});

  @override
  State<Reloading<T>> createState() => _ReloadingState<T>();
}

class _ReloadingState<T> extends State<Reloading<T>> {
  Future<T>? _future;
  int? _revision;
  Object? _deps;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    if (_future == null || _revision != c.revision || _deps != widget.deps) {
      _revision = c.revision;
      _deps = widget.deps;
      _future = widget.loader(c);
    }
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Något gick fel när uppgifterna lästes in.\n${snap.error}')));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return widget.builder(context, snap.data as T);
      },
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyState({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      );
}

Future<bool> confirmDialog(BuildContext context,
    {required String title, required String message, required String confirm}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Avbryt')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(confirm)),
      ],
    ),
  );
  return ok == true;
}
