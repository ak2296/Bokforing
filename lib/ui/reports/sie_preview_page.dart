import 'package:flutter/material.dart';

import '../../export/sie_export.dart';
import '../app_icons.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// The verifications the SIE file will hold, shown before it is sent to the
/// redovisare: series and number, date, text, and each account with debit and
/// credit. These are the same lines the file is built from.
class SiePreviewPage extends StatelessWidget {
  final String period;
  final List<SieVoucher> vouchers;
  const SiePreviewPage({super.key, required this.period, required this.vouchers});

  static const _series = {
    'A': 'Dagskassor (Z-rapporter)',
    'B': 'Onlineförsäljning',
    'C': 'Leverantörsfakturor och betalningar',
    'D': 'Lönebesked',
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final unbalanced = vouchers.where((v) => !v.balances).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Förhandsvisa SIE')),
      body: SafeArea(
        child: vouchers.isEmpty
            ? const EmptyState(icon: AppIcons.file, text: 'Inga verifikationer i perioden.')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: vouchers.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) return _summary(context, t, unbalanced);
                  return _VoucherCard(vouchers[i - 1]);
                },
              ),
      ),
    );
  }

  Widget _summary(BuildContext context, TextTheme t, int unbalanced) {
    final counts = <String, int>{};
    for (final v in vouchers) {
      counts[v.series] = (counts[v.series] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$period: ${vouchers.length} verifikationer', style: t.titleSmall),
            const SizedBox(height: 6),
            for (final e in counts.entries)
              Text('${e.key}  ${_series[e.key] ?? e.key}: ${e.value}', style: t.bodySmall),
            const SizedBox(height: 8),
            Row(children: [
              Icon(unbalanced == 0 ? AppIcons.checkCircle : AppIcons.warning,
                  size: 18, color: unbalanced == 0 ? AppTheme.seed : AppTheme.danger),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  unbalanced == 0
                      ? 'Alla verifikationer balanserar: debet är lika med kredit.'
                      : '$unbalanced verifikationer balanserar inte. Kontrollera dem innan filen skickas.',
                  style: t.bodySmall?.copyWith(color: unbalanced == 0 ? null : AppTheme.danger),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text('Så här kommer filen att se ut hos redovisaren. Kontona är förslag som redovisaren bekräftar.',
                style: t.bodySmall),
          ]),
        ),
      ),
    );
  }
}

class _VoucherCard extends StatelessWidget {
  final SieVoucher v;
  const _VoucherCard(this.v);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final bad = !v.balances;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        margin: EdgeInsets.zero,
        color: bad ? AppTheme.dangerTint : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppTheme.tint, borderRadius: BorderRadius.circular(8)),
                child: Text('${v.series}${v.number}', style: t.labelLarge?.copyWith(color: AppTheme.seed)),
              ),
              const SizedBox(width: 8),
              Text(v.date, style: t.bodySmall),
            ]),
            const SizedBox(height: 4),
            Text(v.text, style: t.titleSmall),
            const SizedBox(height: 8),
            _row(t, 'Konto', 'Debet', 'Kredit', head: true),
            for (final r in v.lines)
              _row(t, '${r.account} ${r.name}', r.debit.isZero ? '' : r.debit.format(unit: false),
                  r.credit.isZero ? '' : r.credit.format(unit: false)),
            const Divider(height: 12),
            _row(t, 'Summa', v.debit.format(unit: false), v.credit.format(unit: false), head: true),
            if (bad)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Skillnad: ${(v.debit - v.credit).format()}', style: t.bodySmall?.copyWith(color: AppTheme.danger)),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _row(TextTheme t, String account, String debit, String credit, {bool head = false}) {
    final style = head ? t.bodySmall?.copyWith(fontWeight: FontWeight.w600) : t.bodySmall;
    final money = style?.merge(moneyStyle);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(account, style: style, maxLines: 2, overflow: TextOverflow.ellipsis)),
        SizedBox(width: 84, child: Text(debit, textAlign: TextAlign.right, style: head ? style : money)),
        SizedBox(width: 84, child: Text(credit, textAlign: TextAlign.right, style: head ? style : money)),
      ]),
    );
  }
}
