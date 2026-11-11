import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/payslip_parser.dart';
import '../../domain/text_patterns.dart';
import '../scan/scan_context.dart';
import '../scan/scan_flow.dart';
import '../settings/activation_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/fields.dart';
import 'review_common.dart';

/// "Kontrollera uppgifterna" for a lönebesked: scan, manual entry or editing a
/// saved one. The cost is bruttolön plus arbetsgivaravgift, on the payout
/// date. Preliminär skatt is kept for the report to Skatteverket. A lönebesked
/// has no moms, so there is no moms field and no "Ingen moms" switch.
class PayslipReviewPage extends StatefulWidget {
  final PayslipDraft? draft;
  final ScanContext? scan;
  final Payslip? existing;
  const PayslipReviewPage({super.key, this.draft, this.scan, this.existing});

  @override
  State<PayslipReviewPage> createState() => _PayslipReviewPageState();
}

class _PayslipReviewPageState extends State<PayslipReviewPage> {
  final _form = GlobalKey<FormState>();
  final _dateKey = GlobalKey();
  final _grossKey = GlobalKey();
  final _feeKey = GlobalKey();
  final _taxKey = GlobalKey();
  late final TextEditingController _name, _pnr, _from, _to, _payout, _gross, _fee, _tax;
  bool _edited = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    final e = widget.existing;
    String money(Money? m) => m?.toInput() ?? '';
    _name = TextEditingController(text: e?.employeeName ?? d?.employeeName.value ?? '');
    _pnr = TextEditingController(text: e?.personnummer ?? d?.personnummer.value ?? '');
    _from = TextEditingController(text: e?.periodFrom ?? d?.periodFrom.value ?? '');
    _to = TextEditingController(text: e?.periodTo ?? d?.periodTo.value ?? '');
    _payout = TextEditingController(
        text: e?.payoutDate ?? d?.payoutDate.value ?? (d == null ? SwedishDates.iso(DateTime.now()) : ''));
    _gross = TextEditingController(text: money(e?.gross ?? d?.gross.value));
    _fee = TextEditingController(text: money(e?.employerFee ?? d?.employerFee.value));
    _tax = TextEditingController(text: money(e?.tax ?? d?.tax.value));
  }

  @override
  void dispose() {
    for (final c in [_name, _pnr, _from, _to, _payout, _gross, _fee, _tax]) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed([String? _]) => setState(() => _edited = true);

  String? _validDate(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : (SwedishDates.isValidIso(t) ? t : null);
  }

  Future<void> _save() async {
    if (!await requireLicense(context) || !mounted) return;
    final payout = _payout.text.trim();
    if (!SwedishDates.isValidIso(payout)) {
      _blocked('Fyll i utbetalningsdatum innan du sparar.', _dateKey);
      return;
    }
    final gross = Money.parse(_gross.text);
    if (gross == null || gross.isZero) {
      _blocked('Fyll i bruttolönen innan du sparar.', _grossKey);
      return;
    }
    final fee = Money.parse(_fee.text);
    if (fee == null) {
      _blocked('Fyll i arbetsgivaravgiften, eller 0 om den saknas.', _feeKey);
      return;
    }
    final tax = Money.parse(_tax.text);
    if (tax == null) {
      _blocked('Fyll i preliminär skatt, eller 0 om den saknas.', _taxKey);
      return;
    }
    final controller = AppScope.read(context);
    final payslip = Payslip(
      id: widget.existing?.id,
      employeeName: _name.text.trim(),
      personnummer: _pnr.text.trim(),
      periodFrom: _validDate(_from),
      periodTo: _validDate(_to),
      payoutDate: payout,
      gross: gross,
      employerFee: fee,
      tax: tax,
      meta: RecordMeta(
        source: widget.existing?.meta.source ?? (widget.scan == null ? RecordSource.manual : RecordSource.ocr),
        manuallyEdited: _edited,
        scanId: widget.existing?.meta.scanId,
      ),
    );
    final dupes = await controller.repo.findDuplicatePayslips(payslip);
    if (dupes.isNotEmpty && mounted) {
      final choice = await duplicateDialog(context,
          title: 'Det här lönebeskedet kan redan vara registrerat.',
          showExistingAvailable: false,
          lines: [for (final p in dupes) '${p.payoutDate} · ${p.employeeName} · ${p.gross.format()}']);
      if (choice != DuplicateChoice.saveAnyway || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      final scanId = await widget.scan?.persist(controller);
      await controller.repo.savePayslip(Payslip(
        id: payslip.id,
        employeeName: payslip.employeeName,
        personnummer: payslip.personnummer,
        periodFrom: payslip.periodFrom,
        periodTo: payslip.periodTo,
        payoutDate: payslip.payoutDate,
        gross: payslip.gross,
        employerFee: payslip.employerFee,
        tax: payslip.tax,
        meta: scanId == null ? payslip.meta : payslip.meta.copyWith(scanId: scanId),
      ));
      controller.dataChanged();
      if (!mounted) return;
      showSaved(context, date: payout);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Det gick inte att spara: $e')));
    }
  }

  Future<void> _delete() async {
    final controller = AppScope.read(context);
    final navigator = Navigator.of(context);
    final ok = await confirmDialog(context,
        title: 'Ta bort lönebeskedet?',
        message: 'Det tas bort från utgifterna och rapporterna. Borttagningen sparas i ändringshistoriken.',
        confirm: 'Ta bort');
    if (!ok) return;
    await controller.repo.deletePayslip(widget.existing!.id!);
    controller.dataChanged();
    navigator.pop();
  }

  void _blocked(String message, GlobalKey key) {
    _form.currentState?.validate();
    showBlocked(context, message, key);
  }

  Widget _summary(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final gross = Money.parse(_gross.text);
    final fee = Money.parse(_fee.text);
    final tax = Money.parse(_tax.text);
    Widget row(String label, Money? v, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(label, style: strong ? t.titleSmall : t.bodyMedium)),
            Text(v == null ? '–' : v.format(), style: moneyStyle.copyWith(fontWeight: strong ? FontWeight.bold : null)),
          ]),
        );
    final printedNet = widget.draft?.net.value;
    final net = gross != null && tax != null ? gross - tax : null;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          row('Kostnad för företaget (utgift)', gross != null && fee != null ? gross + fee : null, strong: true),
          Text('Bruttolön plus arbetsgivaravgift, utan moms. Läggs i Utgifter som Löner och Sociala avgifter.',
              style: t.bodySmall),
          const Divider(height: 20),
          row('Betalas ut till den anställde', net),
          row('Preliminär skatt att redovisa till Skatteverket', tax),
          if (printedNet != null && net != null && printedNet != net)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Nettolönen på pappret är ${printedNet.format()}, inte bruttolön minus skatt. Jämför med bilden.',
                  style: t.bodySmall?.copyWith(color: AppTheme.warning)),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final suggestion = d?.periodToSuggestion;
    Confidence? conf(Extracted<Object?>? e) =>
        widget.scan == null || e == null ? null : (e.hasValue ? e.confidence : Confidence.low);
    return ReviewScaffold(
      title: widget.existing != null ? 'Redigera lönebesked' : 'Kontrollera uppgifterna',
      scan: widget.scan,
      editing: true,
      saving: _saving,
      onSave: _save,
      onRescan: widget.scan == null ? null : () => _rescan(context),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DocTypeHeader(label: 'Lönebesked'),
            if (d != null)
              for (final n in d.notes) NoteCard(n),
            PlainField(
                controller: _name,
                label: 'Anställd',
                confidence: conf(d?.employeeName),
                onChanged: _changed),
            const SizedBox(height: 12),
            PlainField(
                controller: _pnr,
                label: 'Personnummer',
                confidence: conf(d?.personnummer),
                keyboardType: TextInputType.number,
                onChanged: _changed),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: _dateKey,
              child: DateField(
                  controller: _payout,
                  label: 'Utbetalningsdatum (kostnaden räknas till den månaden)',
                  confidence: conf(d?.payoutDate),
                  onChanged: _changed),
            ),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: DateField(
                    controller: _from,
                    label: 'Löneperiod från',
                    confidence: conf(d?.periodFrom),
                    required: false,
                    onChanged: _changed),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DateField(
                    controller: _to,
                    label: 'till',
                    confidence: conf(d?.periodTo),
                    required: false,
                    onChanged: _changed),
              ),
            ]),
            if (suggestion != null && _to.text.trim() != suggestion)
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  label: Text('Använd $suggestion'),
                  onPressed: () => setState(() {
                    _to.text = suggestion;
                    _edited = true;
                  }),
                ),
              ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: _grossKey,
              child: MoneyField(
                  controller: _gross,
                  label: 'Bruttolön',
                  confidence: conf(d?.gross),
                  onChanged: _changed),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: _feeKey,
              child: MoneyField(
                  controller: _fee,
                  label: d?.feeRate == null
                      ? 'Arbetsgivaravgift'
                      : 'Arbetsgivaravgift (${d!.feeRate!.toStringAsFixed(2).replaceAll('.', ',')} % på pappret)',
                  confidence: conf(d?.employerFee),
                  onChanged: _changed),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: _taxKey,
              child: MoneyField(
                  controller: _tax,
                  label: 'Preliminär skatt',
                  confidence: conf(d?.tax),
                  onChanged: _changed),
            ),
            const SizedBox(height: 16),
            _summary(context),
            const SizedBox(height: 8),
            Text('Ett lönebesked har ingen moms.', style: Theme.of(context).textTheme.bodySmall),
            if (widget.existing != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _delete, child: const Text('Ta bort lönebeskedet')),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _rescan(BuildContext context) async {
    final navigator = Navigator.of(context);
    await widget.scan?.discardImages();
    navigator.pop();
    await startScan(navigator.context);
  }
}
