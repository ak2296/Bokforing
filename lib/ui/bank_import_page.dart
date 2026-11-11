import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../domain/bank_matcher.dart';
import '../domain/bank_statement.dart';
import 'app_icons.dart';
import 'theme.dart';

/// Reads a CSV file from the internet bank and offers to mark the unpaid
/// invoices it pays as paid. The file is read in memory and nothing from it
/// is saved; only the invoices the user ticks are changed.
class BankImportPage extends StatefulWidget {
  const BankImportPage({super.key});

  @override
  State<BankImportPage> createState() => _BankImportPageState();
}

class _BankImportPageState extends State<BankImportPage> {
  BankStatement? _statement;
  BankMatchResult? _result;
  final Set<int> _ticked = {};
  String? _error;
  bool _busy = false;

  Future<void> _pick() async {
    final controller = AppScope.read(context);
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt']);
    final path = picked.firstOrNull?.path;
    if (path == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final statement = BankStatement.parse(await File(path).readAsBytes());
      final result = BankMatcher.match(statement.rows, await controller.repo.unpaidInvoices());
      if (!mounted) return;
      setState(() {
        _statement = statement;
        _result = result;
        _ticked
          ..clear()
          ..addAll([
            for (final (i, m) in result.matches.indexed)
              if (m.sure) i,
          ]);
        _busy = false;
      });
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Filen kunde inte läsas: $e';
          _busy = false;
        });
      }
    }
  }

  Future<void> _apply() async {
    final result = _result;
    if (result == null || _ticked.isEmpty) return;
    final controller = AppScope.read(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final chosen = [for (final i in _ticked.toList()..sort()) result.matches[i]];
    for (final m in chosen) {
      await controller.repo.setInvoicePaid(m.invoice.id!, paid: true, paidDate: m.row.date);
    }
    controller.dataChanged();
    navigator.pop();
    messenger.showSnackBar(SnackBar(
        content: Text('${chosen.length} ${chosen.length == 1 ? 'faktura markerad' : 'fakturor markerade'} som betalda.')));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Betalningar från bank')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (result == null) ...[
                  Text(
                    'Välj en CSV-fil du har hämtat från internetbanken (kontohändelser eller kontoutdrag). Appen '
                    'letar efter betalningar som är exakt lika stora som obetalda fakturor och föreslår att de markeras '
                    'som betalda. Filen sparas inte i appen.',
                    style: t.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(AppIcons.file),
                    label: const Text('Välj fil'),
                    onPressed: _pick,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: t.bodyMedium?.copyWith(color: AppTheme.pumpkinText)),
                  ],
                ] else ...[
                  Text('${_statement!.rows.length} betalningar lästa.', style: t.bodySmall),
                  for (final w in _statement!.warnings)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.pumpkinTint,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.pumpkinBorder),
                      ),
                      child: Text(w, style: t.bodySmall?.copyWith(color: AppTheme.pumpkinText)),
                    ),
                  const SizedBox(height: 16),
                  Text('Betalar obetalda fakturor (${result.matches.length})', style: t.titleSmall),
                  if (result.matches.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Ingen betalning är exakt lika stor som en obetald faktura.'),
                    ),
                  for (final (i, m) in result.matches.indexed)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _ticked.contains(i),
                      onChanged: (v) => setState(() => v == true ? _ticked.add(i) : _ticked.remove(i)),
                      title: Text('${m.invoice.supplier.isEmpty ? 'Faktura' : m.invoice.supplier} · ${m.invoice.total.format()}'),
                      subtitle: Text(
                        'Betald ${m.row.date}${m.sure ? '' : ' · osäker koppling, kontrollera'}\n${m.row.text}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (result.matches.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      icon: const Icon(AppIcons.check),
                      label: Text(_ticked.isEmpty ? 'Markera som betalda' : 'Markera ${_ticked.length} som betalda'),
                      onPressed: _ticked.isEmpty ? null : _apply,
                    ),
                  ],
                  const SizedBox(height: 20),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: Text('Utbetalningar utan faktura (${result.unmatchedOut.length})', style: t.titleSmall),
                    subtitle: const Text('Betalningar som inte hör till någon obetald faktura. Saknas ett underlag?'),
                    children: [
                      for (final r in result.unmatchedOut)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(r.text.isEmpty ? '(ingen text)' : r.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(r.date),
                          trailing: Text(r.amount.format(), style: t.bodyMedium),
                        ),
                    ],
                  ),
                  if (result.unmatchedIn > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('${result.unmatchedIn} inbetalningar visas inte.', style: t.bodySmall),
                    ),
                ],
              ],
            ),
    );
  }
}
