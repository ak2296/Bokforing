import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../data/balances_store.dart';
import '../../domain/balances.dart';
import '../../domain/dates.dart';
import '../../domain/money.dart';
import '../app_icons.dart';
import '../theme.dart';
import '../widgets/blur_overlay.dart';

/// Inställningar → Företag → Ingående balanser: what the owner knows on the
/// first day of the financial year. The balance sheet is built from this.
class BalancesPage extends StatefulWidget {
  const BalancesPage({super.key});

  @override
  State<BalancesPage> createState() => _BalancesPageState();
}

class _BalancesPageState extends State<BalancesPage> {
  OpeningBalances? _b;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_b == null) _load();
  }

  Future<void> _load() async {
    final b = await loadBalances(AppScope.read(context).repo);
    if (mounted) setState(() => _b = b);
  }

  Future<void> _save(OpeningBalances b) async {
    setState(() => _b = b);
    await saveBalances(AppScope.read(context).repo, b);
  }

  Future<void> _pickDate() async {
    final b = _b!;
    final current = SwedishDates.parseIso(b.date) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      helpText: 'Datum för balanserna',
    );
    if (d != null) await _save(b.onDate(SwedishDates.iso(d)));
  }

  Future<void> _edit({BalanceEntry? entry, required bool asset}) async {
    final result = await showBlurSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EntrySheet(entry: entry, asset: asset, date: _b!.date),
    );
    if (result is BalanceEntry) await _save(_b!.withEntry(result));
    if (result == 'delete' && entry != null) await _save(_b!.without(entry.id));
  }

  @override
  Widget build(BuildContext context) {
    final b = _b;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ingående balanser')),
      body: b == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                    'Fyll i det du vet den dag räkenskapsåret började. Det du inte vet kan din redovisare fylla i. Balansräkningen i Rapporter bygger på detta.',
                    style: t.bodyMedium),
                const SizedBox(height: 10),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(AppIcons.calendar),
                    title: const Text('Datum för balanserna'),
                    subtitle: Text(b.date),
                    trailing: const Icon(AppIcons.chevronRight),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(height: 10),
                _equityBar(context, b),
                const SizedBox(height: 10),
                _group(context, 'Tillgångar', b.entries.where((e) => e.kind.isAsset).toList(), asset: true, total: b.assets),
                const SizedBox(height: 10),
                _group(context, 'Skulder', b.entries.where((e) => !e.kind.isAsset).toList(), asset: false, total: b.debts),
                const SizedBox(height: 10),
                _plans(context, b),
              ],
            ),
    );
  }

  /// Equity is what is left: assets minus debts. No input needed.
  Widget _equityBar(BuildContext context, OpeningBalances b) {
    final negative = b.equity.isNegative;
    final color = negative ? AppTheme.warning : AppTheme.seed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: negative ? AppTheme.warningTint : AppTheme.tint, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(negative ? AppIcons.warning : AppIcons.checkCircle, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
              negative
                  ? 'Skulderna är större än tillgångarna. Kontrollera beloppen.'
                  : 'Eget kapital räknas ut: tillgångar minus skulder.',
              style: TextStyle(color: color, fontSize: 13)),
        ),
        Text(b.equity.format(), style: moneyStyle.copyWith(color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _group(BuildContext context, String title, List<BalanceEntry> entries, {required bool asset, required Money total}) {
    final t = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title.toUpperCase(), style: t.labelMedium?.copyWith(color: AppTheme.muted, letterSpacing: 0.4))),
            if (entries.isNotEmpty) Text(total.format(), style: moneyStyle.copyWith(fontWeight: FontWeight.w600)),
          ]),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(asset ? 'Inget inlagt. Lägg till bank, kassa, utrustning, lager eller fordringar.' : 'Inget inlagt. Lägg till lån och skulder.',
                  style: t.bodySmall),
            ),
          for (final e in entries)
            InkWell(
              onTap: () => _edit(entry: e, asset: asset),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.name.isEmpty ? e.kind.label : e.name),
                      Text(_detail(e), style: t.bodySmall),
                    ]),
                  ),
                  Text(e.amount.format(), style: moneyStyle.copyWith(fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              icon: const Icon(AppIcons.add, size: 18),
              label: Text(asset ? 'Lägg till tillgång' : 'Lägg till skuld'),
              onPressed: () => _edit(asset: asset),
            ),
          ),
        ]),
      ),
    );
  }

  String _detail(BalanceEntry e) => [
        e.kind.label,
        'konto ${e.kind.account}',
        if (e.years != null) '${e.years} år kvar',
        if (e.monthsLeft != null) '${e.monthsLeft} mån kvar',
        if (e.ratePercent != null) '${e.ratePercent.toString().replaceAll('.', ',')} % ränta',
      ].join(' · ');

  /// Plans the entries give: write-off per year and the first month of a loan.
  Widget _plans(BuildContext context, OpeningBalances b) {
    final t = Theme.of(context).textTheme;
    final start = (SwedishDates.parseIso(b.date) ?? DateTime.now()).year;
    final lines = <Widget>[];
    for (final e in b.entries) {
      final plan = depreciationPlan(e, start);
      if (plan.isNotEmpty) {
        lines.add(Text('${e.name.isEmpty ? e.kind.label : e.name}: ${plan.first.amount.format()} per år i ${plan.length} år.', style: t.bodyMedium));
      }
      final loan = loanFirstMonth(e);
      if (loan != null) {
        lines.add(Text(
            '${e.name.isEmpty ? e.kind.label : e.name}: amortering ${loan.amortisation.format()} och ränta ca ${loan.interest.format()} första månaden.',
            style: t.bodyMedium));
      }
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('AVSKRIVNING OCH LÅN', style: t.labelMedium?.copyWith(color: AppTheme.muted, letterSpacing: 0.4)),
          const SizedBox(height: 6),
          for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 4), child: l),
          Text('Bara en plan. Din redovisare bokför avskrivningar och räntor.', style: t.bodySmall),
        ]),
      ),
    );
  }
}

class _EntrySheet extends StatefulWidget {
  final BalanceEntry? entry;
  final bool asset;
  final String date;
  const _EntrySheet({required this.entry, required this.asset, required this.date});

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  late BalanceKind _kind = widget.entry?.kind ?? (widget.asset ? BalanceKind.bank : BalanceKind.loan);
  late final _name = TextEditingController(text: widget.entry?.name ?? '');
  late final _amount = TextEditingController(text: widget.entry == null ? '' : '${widget.entry!.amount.ore / 100}'.replaceAll('.', ','));
  late final _years = TextEditingController(text: widget.entry?.years?.toString() ?? '');
  late final _months = TextEditingController(text: widget.entry?.monthsLeft?.toString() ?? '');
  late final _rate = TextEditingController(text: widget.entry?.ratePercent?.toString().replaceAll('.', ',') ?? '');
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _amount, _years, _months, _rate]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final amount = Money.parse(_amount.text.trim());
    if (amount == null || amount.ore <= 0) {
      setState(() => _error = 'Skriv ett belopp i kronor.');
      return;
    }
    Navigator.pop(
      context,
      BalanceEntry(
        id: widget.entry?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        kind: _kind,
        name: _name.text.trim(),
        amount: amount,
        years: _kind == BalanceKind.asset ? int.tryParse(_years.text.trim()) : null,
        monthsLeft: _kind == BalanceKind.loan ? int.tryParse(_months.text.trim()) : null,
        ratePercent: _kind == BalanceKind.loan ? double.tryParse(_rate.text.trim().replaceAll(',', '.')) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kinds = [for (final k in BalanceKind.values) if (k.isAsset == widget.asset) k];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.entry == null ? (widget.asset ? 'Ny tillgång' : 'Ny skuld') : 'Ändra',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final k in kinds)
              ChoiceChip(label: Text(k.label), selected: k == _kind, onSelected: (_) => setState(() => _kind = k)),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _name, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: 'Namn (valfritt)', hintText: _kind.label)),
          const SizedBox(height: 10),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Belopp den ${widget.date} (kr)', errorText: _error),
          ),
          if (_kind == BalanceKind.asset) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _years,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Återstående år att skriva av (valfritt)', helperText: 'Appen visar en avskrivningsplan.'),
            ),
          ],
          if (_kind == BalanceKind.loan) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                    controller: _rate,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Ränta per år (%)')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                    controller: _months, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Månader kvar')),
              ),
            ]),
          ],
          const SizedBox(height: 14),
          Row(children: [
            if (widget.entry != null)
              TextButton(onPressed: () => Navigator.pop(context, 'delete'), child: Text('Ta bort', style: TextStyle(color: AppTheme.danger))),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Avbryt')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _save, child: const Text('Spara')),
          ]),
        ]),
      ),
    );
  }
}
