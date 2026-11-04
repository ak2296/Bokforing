import 'package:flutter/material.dart';

import '../domain/dates.dart';
import '../domain/license.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'app_icons.dart';
import 'history_page.dart';
import 'record_details.dart';
import 'settings/activation_page.dart';
import 'theme.dart';
import 'unpaid_page.dart';
import 'widgets/common.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ym = YearMonth.now();
    return Reloading<(MonthData, List<RegistrationSummary>, int, List<Invoice>, LicenseState)>(
      deps: ym.title,
      loader: (c) async => (
        await MonthData.load(c, ym),
        await c.repo.recentRegistrations(limit: 8),
        await c.repo.documentCount(fromIso: ym.firstDay, toIso: ym.lastDay),
        await c.repo.unpaidInvoices(),
        await c.repo.licenseState(),
      ),
      builder: (context, data) {
        final (month, recent, count, unpaid, license) = data;
        final r = month.report;
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
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.7,
              children: [
                _StatCard('Försäljning denna månad', r.totalAllSales),
                _StatCard('Utgifter denna månad', r.totalExpenses),
                _StatCard(diff.isNegative ? 'Momsskillnad (att få tillbaka)' : 'Momsskillnad (att betala)', diff),
                _CountCard('Antal skannade dokument', count),
              ],
            ),
            const SizedBox(height: 8),
            Text('Beräknad moms. Ersätter inte momsdeklarationen.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: Text('Senaste registreringar', style: Theme.of(context).textTheme.titleMedium)),
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

class _StatCard extends StatelessWidget {
  final String label;
  final Money value;
  const _StatCard(this.label, this.value);

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall, maxLines: 2),
              FittedBox(
                child: Text(value.format(compact: true),
                    style: Theme.of(context).textTheme.titleLarge?.merge(moneyStyle)),
              ),
            ],
          ),
        ),
      );
}

class _CountCard extends StatelessWidget {
  final String label;
  final int value;
  const _CountCard(this.label, this.value);

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall, maxLines: 2),
              Text('$value', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
      );
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
