import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../data/bank_match_store.dart';
import '../../data/vat_manual_store.dart';
import '../../domain/ledger.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/report_period.dart';
import '../../export/moms_xml.dart';
import '../../export/redovisar_package.dart';
import '../../export/table_export.dart';
import '../app_icons.dart';
import '../export_actions.dart';
import '../theme.dart';
import '../unpaid_page.dart';
import '../widgets/common.dart';
import 'moms_file_page.dart';
import 'package_page.dart';
import 'report_hero.dart';

/// The Moms tab: moms to pay for the period (from what is registered plus the owner's own
/// figures), per rate, the file for Skatteverket and the Momsunderlag report.
class MomsTab extends StatefulWidget {
  final ReportPeriod period;
  final Ledger ledger;
  final BusinessProfile profile;
  const MomsTab({super.key, required this.period, required this.ledger, required this.profile});

  @override
  State<MomsTab> createState() => _MomsTabState();
}

class _MomsTabState extends State<MomsTab> {
  Map<int, int>? _manual;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MomsTab old) {
    super.didUpdateWidget(old);
    if (old.period.fileTag != widget.period.fileTag) _load();
  }

  Future<void> _load() async {
    final m = await loadVatManual(AppScope.read(context).repo, widget.period.fileTag);
    if (mounted) setState(() => _manual = m);
  }

  Future<void> _editManual() async {
    final result = await Navigator.of(context).push<Map<int, int>>(MaterialPageRoute(builder: (_) => VatManualPage(initial: _manual ?? {})));
    if (result == null || !mounted) return;
    await saveVatManual(AppScope.read(context).repo, widget.period.fileTag, result);
    if (mounted) setState(() => _manual = result);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final manual = _manual;
    if (manual == null) return const Center(child: CircularProgressIndicator());
    final period = widget.period;
    final r = VatReturn.fromLedger(widget.ledger, period, '', manual: manual);
    final out = r.toPay + r.input;
    String kr(int v) => Money.kr(v).format(compact: true);
    Widget row(String label, int v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [Expanded(child: Text(label)), Text(kr(v), style: moneyStyle)]),
        );
    final table = vatBasisTable(widget.ledger, period.title);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 112),
      children: [
        ReportHero(
          color: AppTheme.compare,
          label: '${r.toPay < 0 ? 'Moms att få tillbaka' : 'Moms att betala'}, ${period.title} (beräknad)',
          value: Money.kr(r.toPay.abs()).format(),
          chips: [('Utgående moms', kr(out)), ('Ingående moms', kr(r.input))],
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('PER SATS', style: t.labelMedium?.copyWith(color: AppTheme.muted, letterSpacing: 0.4)),
              row('Utgående 25 %', r.outHigh),
              row('Utgående 12 %', r.outMid),
              row('Utgående 6 %', r.outLow),
              if (out - r.outHigh - r.outMid - r.outLow != 0) row('Utgående, dina egna uppgifter', out - r.outHigh - r.outMid - r.outLow),
              row('Ingående moms', -r.input),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        if (VatReturn.supports(period.kind))
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.compare),
            icon: const Icon(AppIcons.cloudUpload, size: 18),
            label: const Text('Momsfil till Skatteverket'),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => MomsFilePage(period: period, ledger: widget.ledger, profile: widget.profile))),
          )
        else
          Text('Momsfilen görs för en månad, ett kvartal eller ett år. Välj en av dem ovan.', style: t.bodySmall),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(AppIcons.edit, size: 18),
          label: Text(manual.isEmpty ? 'Egna uppgifter (EU-handel m.m.)' : 'Egna uppgifter (${manual.length} rutor)'),
          onPressed: _editManual,
        ),
        const SizedBox(height: 14),
        Text('MOMSUNDERLAG, RUTOR 05–49', style: t.labelMedium?.copyWith(color: AppTheme.muted, letterSpacing: 0.4)),
        const SizedBox(height: 6),
        ExportButtons(
          onPdf: () => exportTablePdf(context, table, widget.profile),
          onExcel: () => exportTableCsv(context, table),
          onPrint: () => printTable(context, table, widget.profile),
        ),
        const SizedBox(height: 12),
        Text('Beräknad moms från det som är registrerat i Quee. Ersätter inte momsdeklarationen.', style: t.bodySmall),
      ],
    );
  }
}

/// The Kontroll tab: everything to look at before the period is handed over, in one list.
/// Each point opens where it is fixed.
class ControlTab extends StatelessWidget {
  final ReportPeriod period;
  const ControlTab({super.key, required this.period});

  @override
  Widget build(BuildContext context) => Reloading<(PackageData, int, BankMatchFlags, List<DailySales>)>(
        deps: '${period.kind.name} ${period.fileTag}',
        loader: (c) async => (
          await loadPackage(c, period),
          (await c.repo.unpaidInvoices()).where((i) => (daysUntil(i.dueDate) ?? 1) < 0).length,
          await loadBankMatch(c.repo),
          await c.repo.dailySalesBetween(period.from, period.to),
        ),
        builder: (context, data) {
          final (d, overdue, flags, sales) = data;
          final t = Theme.of(context).textTheme;
          final missing = d.issues.where((i) => i.text.startsWith('Z-rapport saknas') || i.text.contains('dagar till saknar')).length;
          final fill = d.issues.where((i) => i.target == IssueTarget.invoice).length;
          final open = d.issues.length + (overdue > 0 ? 1 : 0);
          Widget good(String title, String sub) => _Tile(title: title, sub: sub, ok: true);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 112),
            children: [
              ReportHero(
                color: AppTheme.warning,
                label: 'Att se över, ${period.title}',
                value: open == 0 ? 'Allt ser bra ut' : '$open ${open == 1 ? 'sak' : 'saker'}',
                chips: [('Z-rapporter saknas', '$missing'), ('Att fylla i', '$fill'), ('Förfallna', '$overdue')],
              ),
              const SizedBox(height: 12),
              for (final i in d.issues)
                _Tile(
                  title: i.text,
                  sub: switch (i.target) {
                    IssueTarget.zReport => 'Tryck för att öppna Z-rapporten',
                    IssueTarget.invoice => 'Tryck för att fylla i fakturan',
                    IssueTarget.balances => 'Tryck för att lägga in ingående balanser',
                    IssueTarget.none => 'Skanna Z-rapporten, eller markera dagen som stängd under Inställningar',
                  },
                  ok: false,
                  onTap: i.target == IssueTarget.none ? null : () => openReviewIssue(context, i),
                ),
              if (overdue > 0) _Tile(title: '$overdue ${overdue == 1 ? 'faktura har' : 'fakturor har'} förfallit', sub: 'Obetalda fakturor, tryck för listan', ok: false, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UnpaidPage()))),
              if (overdue == 0) good('Obetalda fakturor', 'Inga har förfallit'),
              good('Z-rapporter mot bank', flags.zText(sales) == '–' ? 'Ingen bankfil inläst' : '${flags.zText(sales)} Z-rapportdagar stämmer'),
              const SizedBox(height: 8),
              Text('Det här är samma punkter som i Redovisarpaket. Sådant du inte kan rätta kan du godkänna där.', style: t.bodySmall),
            ],
          );
        },
      );
}

class _Tile extends StatelessWidget {
  final String title;
  final String sub;
  final bool ok;
  final VoidCallback? onTap;
  const _Tile({required this.title, required this.sub, required this.ok, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final color = ok ? AppTheme.seed : AppTheme.warning;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: ok ? AppTheme.surface : AppTheme.warningTint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: ok ? AppTheme.hairline : AppTheme.warningBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(ok ? AppIcons.check : AppIcons.warning, size: 13, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: t.bodyMedium?.copyWith(color: ok ? null : AppTheme.warning)),
                  Text(sub, style: t.bodySmall),
                ]),
              ),
              if (onTap != null) Icon(AppIcons.chevronRight, size: 18, color: color),
            ]),
          ),
        ),
      ),
    );
  }
}
