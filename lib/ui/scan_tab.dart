import 'package:flutter/material.dart';

import 'app_icons.dart';
import 'review/invoice_review_page.dart';
import 'review/online_review_page.dart';
import 'review/z_review_page.dart';
import 'scan/scan_flow.dart';
import 'theme.dart';

/// Scanning and manual entry. Nothing is saved until the user confirms on
/// the review screen.
class ScanTab extends StatelessWidget {
  const ScanTab({super.key});

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Material(
          color: AppTheme.seed,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => startScan(context),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Row(children: [
                Icon(AppIcons.scan, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Skanna faktura eller Z-rapport',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('Appen känner själv igen dokumentet.', style: t.bodySmall),
        const SizedBox(height: 28),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => startScan(context, online: true),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const IconTile(AppIcons.delivery, background: AppTheme.onlineTint, color: AppTheme.online),
                const SizedBox(width: 12),
                Expanded(child: Text('Skanna onlineförsäljning', style: t.titleSmall)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('Foodora och andra partner.', style: t.bodySmall),
        const SizedBox(height: 32),
        Text('Fyll i manuellt', style: t.titleSmall),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                title: const Text('Ny faktura'),
                trailing: const Icon(AppIcons.chevronRight, size: 18),
                onTap: () => _open(context, const InvoiceReviewPage()),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Ny Z-rapport'),
                trailing: const Icon(AppIcons.chevronRight, size: 18),
                onTap: () => _open(context, const ZReviewPage()),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Ny onlineförsäljning'),
                trailing: const Icon(AppIcons.chevronRight, size: 18),
                onTap: () => _open(context, const OnlineReviewPage()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
