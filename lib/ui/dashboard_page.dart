import 'package:flutter/material.dart';

import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'history_page.dart';
import 'unpaid_page.dart';
import 'record_details.dart';
import 'theme.dart';
import 'widgets/common.dart';

class DashboardPage extends StatelessWidget {
  final VoidCallback onScan;
  const DashboardPage({super.key, required this.onScan});

  @override
  Widget build(BuildContext context) {
    final ym = YearMonth.now();
    return Reloading<(MonthData, List<RegistrationSummary>, int, List<Invoice>)>(
      deps: ym.title,
      loader: (c) async => (
        await MonthData.load(c, ym),
        await c.repo.recentRegistrations(limit: 8),
        await c.repo.documentCount(fromIso: ym.firstDay, toIso: ym.lastDay),
        await c.repo.unpaidInvoices(),
      ),
      builder: (context, data) {
        final (month, recent, count, unpaid) = data;
        final r = month.report;
        final diff = r.vatDifference;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (month.profile.name.isNotEmpty)
              Text(month.profile.name.toUpperCase(), style: Theme.of(context).textTheme.titleMedium),
            Text(ym.title, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: onScan,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Skanna dokument'),
            ),
            if (unpaid.isNotEmpty) _UnpaidCard(unpaid),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.7,
              children: [
                _StatCard('Försäljning denna månad', r.totalSales),
                _StatCard('Utgifter denna månad', r.totalExpenses),
                _StatCard('Utgående moms', r.totalOutputVat),
                _StatCard('Ingående moms', r.totalInputVat),
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
              const EmptyState(icon: Icons.inbox_outlined, text: 'Inga registreringar ännu.')
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
        child: Padding(
          padding: const EdgeInsets.all(12),
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
        child: Padding(
          padding: const EdgeInsets.all(12),
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
      leading: Icon(e.kind == 'invoice' ? Icons.receipt_long_outlined : Icons.point_of_sale_outlined),
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
          leading: Icon(Icons.payments_outlined, color: urgent ? color : null),
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
