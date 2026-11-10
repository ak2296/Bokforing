import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'app_icons.dart';
import 'review/invoice_review_page.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/ledger_parts.dart';

/// Invoices and receipts that lack something the reports need (cost type,
/// supplier, date, amount or moms). Tapping one opens it for editing.
class IncompletePage extends StatelessWidget {
  final String from;
  final String to;
  final String? period;
  const IncompletePage({super.key, this.from = '0000-01-01', this.to = '9999-12-31', this.period});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Saknar uppgifter')),
        body: Reloading<List<Invoice>>(
          deps: '$from$to',
          loader: (c) async => (await c.repo.invoicesBetween(from, to)).where((i) => i.isIncomplete).toList()
            ..sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate)),
          builder: (context, list) {
            if (list.isEmpty) {
              return const EmptyState(icon: AppIcons.checkCircle, text: 'Alla fakturor och kvitton är kompletta.');
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  '${list.length} dokument saknar uppgifter'
                  '${period == null ? '' : ' ($period)'}. Tryck på ett för att fylla i det som saknas.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                LedgerCard(children: [
                  for (final inv in list)
                    LedgerRow(
                      isoDate: inv.invoiceDate,
                      title: inv.supplier.isEmpty ? 'Okänd leverantör' : inv.supplier,
                      subtitle: 'Saknar: ${inv.missingFields.join(', ')}',
                      amount: inv.total,
                      badgeBackground: AppTheme.warningTint,
                      badgeColor: AppTheme.warning,
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => InvoiceReviewPage(existing: inv))),
                    ),
                ]),
              ],
            );
          },
        ),
      );
}

/// A warning box that opens [IncompletePage]; nothing when [count] is 0.
class IncompleteNotice extends StatelessWidget {
  final int count;
  final String from;
  final String to;
  final String? period;
  const IncompleteNotice({super.key, required this.count, required this.from, required this.to, this.period});

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Material(
      color: AppTheme.warningTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.warningBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => IncompletePage(from: from, to: to, period: period))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Icon(AppIcons.warning, size: 18, color: AppTheme.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$count ${count == 1 ? 'faktura saknar' : 'fakturor saknar'} uppgifter '
                '(kostnadstyp, leverantör, belopp eller moms). Tryck för att rätta.',
                style: const TextStyle(color: AppTheme.warning, fontSize: 13),
              ),
            ),
            const Icon(AppIcons.chevronRight, size: 18, color: AppTheme.warning),
          ]),
        ),
      ),
    );
  }
}
