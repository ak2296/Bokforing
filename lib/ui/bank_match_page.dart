import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../data/bank_match_store.dart';
import '../domain/bank_match.dart';
import '../domain/bank_matcher.dart';
import '../domain/bank_statement.dart';
import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'theme.dart';

/// "Z-rapporter mot bank" (from Försäljning) and "Utgifter mot bank" (from Utgifter):
/// reads a bank file the owner picks and checks it against what is registered. The
/// file is read in memory. Only yes or no per Z-report day and per invoice is kept, so
/// the count in the hero stays; no bank text, amount or balance is saved.
class BankMatchPage extends StatefulWidget {
  /// False: card takings against deposits. True: invoices and receipts paid from the
  /// bank or by card against payments.
  final bool invoices;
  const BankMatchPage({super.key, required this.invoices});

  @override
  State<BankMatchPage> createState() => _BankMatchPageState();
}

class _BankMatchPageState extends State<BankMatchPage> {
  List<ZBankLine>? _zLines;
  List<(Invoice, bool)>? _invRows;
  String? _error;
  bool _busy = false;

  Future<void> _pick() async {
    final c = AppScope.read(context);
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt']);
    final path = picked.firstOrNull?.path;
    if (path == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = BankStatement.parse(await File(path).readAsBytes()).rows;
      final dates = [for (final r in rows) r.date]..sort();
      DateTime day(String iso) => SwedishDates.parseIso(iso)!;
      final first = day(dates.first), last = day(dates.last);
      if (!widget.invoices) {
        // Card takings are paid out a few days later, so look a little before the file starts.
        final sales = await c.repo.dailySalesBetween(SwedishDates.iso(first.subtract(const Duration(days: 20))), SwedishDates.iso(last));
        final lines = ZBankMatcher.matchZ(sales, rows);
        await saveBankMatch(c.repo, z: {
          for (final l in lines)
            for (final d in l.days)
              if (l.matched) d: true else if (!l.pending) d: false,
        });
        if (!mounted) return;
        setState(() => _zLines = lines);
      } else {
        final all = await c.repo.invoicesBetween(SwedishDates.iso(first.subtract(const Duration(days: 3))), SwedishDates.iso(last));
        final paidByBank = [for (final i in all) if (i.id != null && i.paid && i.bankPart > Money.zero) i];
        final found = {for (final e in BankMatcher.match(rows, const [], paidByBank: paidByBank).explained) e.$2.id};
        await saveBankMatch(c.repo, invoices: {for (final i in paidByBank) i.id!: found.contains(i.id)});
        if (!mounted) return;
        setState(() => _invRows = [for (final i in paidByBank) (i, found.contains(i.id))]);
      }
      c.dataChanged();
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Filen kunde inte läsas: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _status(String text, bool good) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: good ? AppTheme.tint : AppTheme.warningTint,
          borderRadius: BorderRadius.circular(8),
          border: good ? null : Border.all(color: AppTheme.warningBorder),
        ),
        child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: good ? AppTheme.seed : AppTheme.warning)),
      );

  Widget _notice(String text) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.warningTint,
          border: Border.all(color: AppTheme.warningBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text, style: TextStyle(color: AppTheme.warning, fontSize: 13.5, height: 1.35)),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final z = _zLines, inv = _invRows;
    final shown = z != null || inv != null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.invoices ? 'Utgifter mot bank' : 'Z-rapporter mot bank')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _notice(widget.invoices
                    ? 'Bankfilen läses bara här. Appen letar efter betalningar som är exakt lika stora som dina kvitton och fakturor som betalats med bank eller kort. Den sparar inte raderna i filen, bara om varje betalning hittades (ja eller nej).'
                    : 'Bankfilen läses bara här. Appen sparar inte raderna i filen, bara om varje Z-rapport stämde (ja eller nej). Kortinsättningar kommer några dagar senare, ibland för flera dagar i ett, minus avgift.'),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: TextStyle(color: AppTheme.danger)),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: Text(shown ? 'Välj en annan bankfil' : 'Välj bankfil (CSV)'),
                  onPressed: _pick,
                ),
                if (z != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: '${z.where((l) => l.matched).fold<int>(0, (a, l) => a + l.days.length)} av ${z.fold<int>(0, (a, l) => a + l.days.length)}', style: t.titleMedium),
                        const TextSpan(text: ' Z-rapportdagar stämmer mot banken'),
                      ])),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: Column(children: [
                        if (z.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Inga Z-rapporter med kortbelopp för de här datumen.')),
                        for (final (i, l) in z.indexed) ...[
                          if (i > 0) Divider(height: 1, color: AppTheme.hairline),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(l.matched ? SwedishDates.mediumDay(l.deposit!.date) : 'Ingen insättning'),
                                  Text(
                                      'Z ${l.days.length == 1 ? SwedishDates.mediumDay(l.days.first) : '${SwedishDates.mediumDay(l.days.first)} – ${SwedishDates.mediumDay(l.days.last)}'}: ${l.expected.format(unit: false, compact: true)}',
                                      style: t.bodySmall),
                                ]),
                              ),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                if (l.matched) ...[
                                  Text(l.deposit!.amount.format(unit: false, compact: true), style: t.titleSmall),
                                  Text('avgift ${l.fee.format(unit: false, compact: true)}', style: t.bodySmall),
                                ] else
                                  Text('saknar ${l.expected.format(unit: false, compact: true)}', style: t.bodySmall),
                              ]),
                              const SizedBox(width: 8),
                              _status(l.matched ? 'Stämmer' : (l.pending ? 'Väntar' : 'Kolla'), l.matched),
                            ]),
                          ),
                        ],
                      ]),
                    ),
                  ),
                  if (z.any((l) => !l.matched && !l.pending)) ...[
                    const SizedBox(height: 10),
                    _notice('En rad som inte stämmer kan vara en insättning som inte finns i filen ännu, en Z-rapport med fel kortbelopp, eller en dag som är betald på annat sätt.'),
                  ],
                ],
                if (inv != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: '${inv.where((e) => e.$2).length} av ${inv.length}', style: t.titleMedium),
                        const TextSpan(text: ' betalda med bank eller kort hittades i filen'),
                      ])),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: Column(children: [
                        if (inv.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Inga kvitton eller fakturor betalda med bank eller kort för de här datumen.')),
                        for (final (i, e) in inv.indexed) ...[
                          if (i > 0) Divider(height: 1, color: AppTheme.hairline),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(e.$1.supplier.isEmpty ? 'Okänd leverantör' : e.$1.supplier),
                                  Text(SwedishDates.mediumDay(e.$1.bookingDate), style: t.bodySmall),
                                ]),
                              ),
                              Text(e.$1.total.format(unit: false, compact: true), style: t.titleSmall),
                              const SizedBox(width: 8),
                              _status(e.$2 ? 'Hittad' : 'Hittades inte', e.$2),
                            ]),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
