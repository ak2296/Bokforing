import 'package:flutter/material.dart';

import 'app_icons.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'record_details.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// Unpaid invoices, earliest due date first, with "Betala" details and
/// "Markera som betald".
class UnpaidPage extends StatelessWidget {
  const UnpaidPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Obetalda fakturor')),
        body: Reloading<List<Invoice>>(
          loader: (c) => c.repo.unpaidInvoices(),
          builder: (context, list) {
            if (list.isEmpty) {
              return const EmptyState(icon: AppIcons.checkCircle, text: 'Inga obetalda fakturor.');
            }
            final total = Money.sum(list.map((i) => i.total));
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    title: const Text('Att betala totalt'),
                    subtitle: Text('${list.length} ${list.length == 1 ? 'faktura' : 'fakturor'}'),
                    trailing: Text(total.format(), style: moneyStyle.copyWith(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 8),
                for (final inv in list) UnpaidTile(invoice: inv),
              ],
            );
          },
        ),
      );
}

/// Days until [isoDate] from today (negative when passed), or null.
int? daysUntil(String? isoDate) {
  final d = isoDate == null ? null : SwedishDates.parseIso(isoDate);
  if (d == null) return null;
  final now = DateTime.now();
  return d.difference(DateTime(now.year, now.month, now.day)).inDays;
}

String dueText(String? dueDate) {
  final days = daysUntil(dueDate);
  if (days == null) return 'Inget förfallodatum';
  if (days < 0) return 'Förföll ${SwedishDates.mediumDay(dueDate!)} (${-days} ${-days == 1 ? 'dag' : 'dagar'} sedan)';
  if (days == 0) return 'Förfaller i dag';
  if (days == 1) return 'Förfaller i morgon';
  return 'Förfaller ${SwedishDates.mediumDay(dueDate!)} (om $days dagar)';
}

class UnpaidTile extends StatelessWidget {
  final Invoice invoice;
  const UnpaidTile({super.key, required this.invoice});

  @override
  Widget build(BuildContext context) {
    final inv = invoice;
    final days = daysUntil(inv.dueDate);
    final color = days == null
        ? null
        : days < 0
            ? Theme.of(context).colorScheme.error
            : days <= 3
                ? AppTheme.warning
                : null;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(days != null && days < 0 ? AppIcons.error : AppIcons.schedule, color: color),
        title: Text(inv.supplier.isEmpty ? 'Faktura' : inv.supplier),
        subtitle: Text(dueText(inv.dueDate), style: TextStyle(color: color)),
        trailing: Text(inv.total.format(compact: true), style: moneyStyle),
        onTap: () => showPaySheet(context, inv),
      ),
    );
  }
}

/// "Betala": everything needed in the bank app, with copy buttons.
Future<void> showPaySheet(BuildContext context, Invoice inv) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(inv.supplier.isEmpty ? 'Faktura' : inv.supplier, style: Theme.of(c).textTheme.titleLarge),
              Text(dueText(inv.dueDate)),
              const SizedBox(height: 12),
              _CopyRow('Belopp', inv.total.toInput(), display: inv.total.format()),
              if (inv.bankgiro.isNotEmpty) _CopyRow('Bankgiro', inv.bankgiro),
              if (inv.plusgiro.isNotEmpty) _CopyRow('Plusgiro', inv.plusgiro),
              if (inv.ocrReference.isNotEmpty) _CopyRow('OCR-nummer', inv.ocrReference),
              if (inv.invoiceNumber.isNotEmpty) _CopyRow('Fakturanummer', inv.invoiceNumber),
              if (inv.bankgiro.isEmpty && inv.plusgiro.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Inget bankgiro eller plusgiro sparat. Se fakturan.'),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(AppIcons.check),
                label: const Text('Markera som betald'),
                onPressed: () async {
                  final controller = AppScope.read(c);
                  final navigator = Navigator.of(c);
                  final messenger = ScaffoldMessenger.of(c);
                  final date = await showDatePicker(
                    context: c,
                    helpText: 'Betalningsdatum',
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (date == null) return;
                  await controller.repo.setInvoicePaid(inv.id!, paid: true, paidDate: SwedishDates.iso(date));
                  controller.dataChanged();
                  navigator.pop();
                  messenger.showSnackBar(const SnackBar(content: Text('Fakturan är markerad som betald.')));
                },
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(c).pop();
                  openRecord(context, 'invoice', inv.id!);
                },
                child: const Text('Visa fakturan'),
              ),
            ],
          ),
        ),
      ),
    );

class _CopyRow extends StatelessWidget {
  final String label;
  final String value;
  final String? display;
  const _CopyRow(this.label, this.value, {this.display});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Text(display ?? value, style: Theme.of(context).textTheme.titleMedium?.merge(moneyStyle)),
        trailing: IconButton(
          tooltip: 'Kopiera $label',
          icon: const Icon(AppIcons.copy),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            await Clipboard.setData(ClipboardData(text: value));
            messenger.showSnackBar(SnackBar(content: Text('$label kopierat.')));
          },
        ),
      );
}
