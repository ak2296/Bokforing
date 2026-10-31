import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/validation.dart';
import 'review/invoice_review_page.dart';
import 'review/z_review_page.dart';
import 'theme.dart';
import 'widgets/common.dart';

Future<void> openRecord(BuildContext context, String kind, int id) =>
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => kind == 'invoice' ? InvoiceDetailsPage(id: id) : DailySalesDetailsPage(id: id)));

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool money;
  const _Row(this.label, this.value, {this.money = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: money ? moneyStyle.copyWith(fontWeight: FontWeight.w600) : null),
            ),
          ],
        ),
      );
}

class ValidationList extends StatelessWidget {
  final List<ValidationResult> results;
  const ValidationList(this.results, {super.key});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final r in results)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                r.isOk ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                color: r.isOk
                    ? AppTheme.ok
                    : r.status == ValidationStatus.error
                        ? Theme.of(context).colorScheme.error
                        : AppTheme.warning,
              ),
              title: Text(r.message),
            ),
        ],
      );
}

Widget _section(BuildContext context, String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              ...children,
            ],
          ),
        ),
      ),
    );

List<Widget> _metaRows(RecordMeta m) => [
      _Row('Källa', m.source.label),
      _Row('Status', m.confirmed ? 'Godkänd' : 'Ej godkänd'),
      _Row('Ändrad efter registrering', m.manuallyEdited ? 'Ja' : 'Nej'),
      if (m.createdAt != null) _Row('Registrerad', _stamp(m.createdAt!)),
      if (m.updatedAt != null) _Row('Senast ändrad', _stamp(m.updatedAt!)),
    ];

String _stamp(DateTime d) =>
    '${SwedishDates.iso(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

Widget _historyAndScan(BuildContext context, String entity, int id, int? scanId) {
  final repo = AppScope.read(context).repo;
  return FutureBuilder<(List<Map<String, Object?>>, Map<String, Object?>?)>(
    future: (() async => (await repo.auditFor(entity, id), scanId == null ? null : await repo.scan(scanId)))(),
    builder: (context, snap) {
      if (!snap.hasData) return const SizedBox.shrink();
      final (audit, scan) = snap.data!;
      const actions = {'create': 'Registrerad', 'update': 'Ändrad', 'delete': 'Borttagen'};
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _section(context, 'Ändringshistorik', [
            for (final a in audit)
              _Row(actions[a['action']] ?? '${a['action']}', _stamp(DateTime.parse(a['at'] as String))),
          ]),
          if (scan != null && (scan['image_path'] as String?) != null)
            _section(context, 'Originalbild', [
              for (final path in (scan['image_path'] as String).split(';')) StoredImage(path),
            ]),
          if (scan != null)
            _section(context, 'Avläst text från dokumentet', [
              SelectableText(scan['ocr_text'] as String,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ]),
        ],
      );
    },
  );
}

class InvoiceDetailsPage extends StatelessWidget {
  final int id;
  const InvoiceDetailsPage({super.key, required this.id});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Faktura')),
        body: Reloading<Invoice?>(
          loader: (c) => c.repo.invoice(id),
          builder: (context, inv) {
            if (inv == null) return const EmptyState(icon: Icons.search_off, text: 'Fakturan finns inte längre.');
            final checks = const AccountingValidationEngine().validateInvoice(inv);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section(context, 'Uppgifter', [
                  _Row('Datum', inv.invoiceDate),
                  if (inv.supplier.isNotEmpty) _Row('Leverantör', inv.supplier),
                  if (inv.invoiceNumber.isNotEmpty) _Row('Fakturanummer', inv.invoiceNumber),
                  if (inv.dueDate != null) _Row('Förfallodatum', inv.dueDate!),
                  if (inv.ocrReference.isNotEmpty) _Row('OCR-nummer', inv.ocrReference),
                  _Row('Summa', inv.total.format(), money: true),
                  _Row(inv.vatCalculated ? 'Moms (beräknad)' : 'Moms', inv.vatTotal.format(), money: true),
                ]),
                if (inv.vatLines.isNotEmpty)
                  _section(context, 'Moms per momssats', [
                    for (final l in inv.vatLines)
                      _Row('${l.rate.label}${l.calculated ? ' (beräknad)' : ''}', l.vat.format(), money: true),
                  ]),
                _section(context, 'Kontroll', [ValidationList(checks)]),
                _section(context, 'Spårbarhet', _metaRows(inv.meta)),
                _historyAndScan(context, 'invoice', id, inv.meta.scanId),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Redigera'),
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => InvoiceReviewPage(existing: inv))),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Ta bort fakturan'),
                  onPressed: () async {
                    final controller = AppScope.read(context);
                    final ok = await confirmDialog(context,
                        title: 'Ta bort fakturan?',
                        message: 'Fakturan tas bort från rapporterna. Borttagningen sparas i ändringshistoriken.',
                        confirm: 'Ta bort');
                    if (!ok) return;
                    await controller.repo.deleteInvoice(id);
                    controller.dataChanged();
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ],
            );
          },
        ),
      );
}

class DailySalesDetailsPage extends StatelessWidget {
  final int id;
  const DailySalesDetailsPage({super.key, required this.id});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Z-rapport')),
        body: Reloading<DailySales?>(
          loader: (c) => c.repo.dailySales(id),
          builder: (context, d) {
            if (d == null) return const EmptyState(icon: Icons.search_off, text: 'Dagen finns inte längre.');
            final checks = const AccountingValidationEngine().validateDailySales(d);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section(context, 'Uppgifter', [
                  _Row('Datum', d.businessDate),
                  if ((d.zNumber ?? '').isNotEmpty) _Row('Z-nummer', d.zNumber!),
                  for (final i in d.items) _Row('${i.categoryName} (${i.vat.label})', i.amount.format(), money: true),
                  const Divider(),
                  _Row('Dagsförsäljning (enligt rapporten)', d.reportedTotal.format(), money: true),
                  _Row('Beräknad detaljerad summa', d.detailedTotal.format(), money: true),
                  _Row('Skillnad', d.difference.format(), money: true),
                ]),
                _section(context, 'Moms', [
                  for (final i in d.items)
                    _Row('${i.categoryName}: moms ${i.vat.label}', i.vatAmount.format(), money: true),
                  const Divider(),
                  _Row('Utgående moms', d.outputVat.format(), money: true),
                  _Row('Försäljning exkl. moms', (d.detailedTotal - d.outputVat).format(), money: true),
                ]),
                _section(context, 'Kontroll', [ValidationList(checks)]),
                if (d.note.isNotEmpty) _section(context, 'Anteckning', [Text(d.note)]),
                _section(context, 'Spårbarhet', _metaRows(d.meta)),
                _historyAndScan(context, 'daily_sales', id, d.meta.scanId),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Redigera'),
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => ZReviewPage(existing: d))),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Ta bort dagen'),
                  onPressed: () async {
                    final controller = AppScope.read(context);
                    final ok = await confirmDialog(context,
                        title: 'Ta bort Z-rapporten?',
                        message: 'Dagen tas bort från rapporterna. Borttagningen sparas i ändringshistoriken.',
                        confirm: 'Ta bort');
                    if (!ok) return;
                    await controller.repo.deleteDailySales(id);
                    controller.dataChanged();
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ],
            );
          },
        ),
      );
}
