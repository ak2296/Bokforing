import 'package:flutter/material.dart';

import 'review/invoice_review_page.dart';
import 'review/z_review_page.dart';
import 'scan/scan_flow.dart';

/// Scanning and manual entry. Nothing is saved until the user confirms on
/// the review screen.
class ScanTab extends StatelessWidget {
  const ScanTab({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
          icon: const Icon(Icons.document_scanner_outlined, size: 28),
          label: const Text('Skanna faktura eller Z-rapport'),
          onPressed: () => startScan(context),
        ),
        const SizedBox(height: 8),
        Text('Appen känner själv igen om det är en faktura eller en Z-rapport.', style: t.bodySmall),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: const Icon(Icons.burst_mode_outlined),
          label: const Text('Långt dokument (flera bilder)'),
          onPressed: () => startScan(context, longDocument: true),
        ),
        const SizedBox(height: 8),
        Text('För långa kvitton och Z-rapporter: ta flera bilder uppifrån och ned.', style: t.bodySmall),
        const SizedBox(height: 28),
        Text('Fyll i manuellt', style: t.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Ny faktura'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InvoiceReviewPage())),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.point_of_sale_outlined),
                title: const Text('Ny Z-rapport'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ZReviewPage())),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
