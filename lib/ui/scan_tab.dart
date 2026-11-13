import 'package:flutter/material.dart';

import '../domain/dates.dart';
import '../domain/models.dart';
import 'app_icons.dart';
import 'record_details.dart';
import 'review/invoice_review_page.dart';
import 'review/online_review_page.dart';
import 'review/payslip_review_page.dart';
import 'review/z_review_page.dart';
import 'scan/scan_flow.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// Scanning and manual entry. The main button sits at the bottom, within
/// reach of the thumb; the other ways in are small tiles above it. Nothing
/// is saved until the user confirms on the review screen.
class ScanTab extends StatelessWidget {
  const ScanTab({super.key});

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  void _manual(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text('Fyll i själv')),
          ),
          for (final (icon, label, page) in [
            (AppIcons.expenses, 'Ny faktura eller kvitto', const InvoiceReviewPage()),
            (AppIcons.register, 'Ny Z-rapport', const ZReviewPage()),
            (AppIcons.delivery, 'Ny onlineförsäljning', const OnlineReviewPage()),
            (AppIcons.payments, 'Nytt lönebesked', const PayslipReviewPage()),
          ])
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              trailing: const Icon(AppIcons.chevronRight, size: 18),
              onTap: () {
                Navigator.pop(sheet);
                _open(context, page);
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 112),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Icon(AppIcons.info, color: AppTheme.seed),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Lägg pappret på en mörk yta i bra ljus. Efter bilden justerar du hörnen.',
                        style: t.bodySmall),
                  ),
                ]),
              ),
            ),
            Reloading<List<RegistrationSummary>>(
              loader: (c) => c.repo.recentRegistrations(limit: 3),
              builder: (context, recent) => recent.isEmpty
                  ? const SizedBox.shrink()
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                        child: Text('Senast registrerat', style: t.titleSmall),
                      ),
                      Card(
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        child: Column(children: [
                          for (final (i, e) in recent.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            ListTile(
                              dense: true,
                              title: Text(e.title.isEmpty ? e.typeLabel : '${e.typeLabel} · ${e.title}',
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(SwedishDates.shortDay(e.date)),
                              trailing: Text(e.amount.format(compact: true), style: moneyStyle),
                              onTap: () => openRecord(context, e.kind, e.id),
                            ),
                          ],
                        ]),
                      ),
                    ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
              child: Text('Annat sätt', style: t.titleSmall),
            ),
            Row(children: [
              _Tile(
                icon: AppIcons.delivery,
                color: AppTheme.online,
                background: AppTheme.onlineTint,
                label: 'Online­försäljning',
                onTap: () => startScan(context, online: true),
              ),
              const SizedBox(width: 8),
              _Tile(icon: AppIcons.file, label: 'Importera fil', onTap: () => importFile(context)),
              const SizedBox(width: 8),
              _Tile(icon: AppIcons.edit, label: 'Fyll i själv', onTap: () => _manual(context)),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Material(
                color: AppTheme.seed,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => startScan(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                    child: Row(children: [
                      const Icon(AppIcons.scan, color: Colors.white, size: 30),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Skanna faktura eller Z-rapport',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                          Text('Appen känner igen dokumentet',
                              style: t.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ]);
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final Color? background;
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.background,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
              child: Column(children: [
                IconTile(icon, background: background ?? AppTheme.tint, color: color ?? AppTheme.seed),
                const SizedBox(height: 8),
                Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.ink)),
              ]),
            ),
          ),
        ),
      );
}
