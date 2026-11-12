import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/online_parser.dart';
import '../../domain/text_patterns.dart';
import '../../domain/vat.dart';
import '../app_icons.dart';
import '../scan/scan_context.dart';
import '../scan/scan_flow.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/fields.dart';
import '../settings/activation_page.dart';
import 'invoice_review_page.dart';
import 'review_common.dart';

/// "Kontrollera uppgifterna" for a partner's payout: scan, manual entry or
/// editing a saved payment.
class OnlineReviewPage extends StatefulWidget {
  final OnlineDraft? draft;
  final ScanContext? scan;
  final OnlineSale? existing;
  const OnlineReviewPage({super.key, this.draft, this.scan, this.existing});

  @override
  State<OnlineReviewPage> createState() => _OnlineReviewPageState();
}

class _OnlineReviewPageState extends State<OnlineReviewPage> {
  final _form = GlobalKey<FormState>();
  final _dateKey = GlobalKey();
  final _amountKey = GlobalKey();
  final _vatKey = GlobalKey();
  late final TextEditingController _date, _partner, _number, _amount, _vat;
  VatRate? _rate;
  late bool _editing;
  bool _edited = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    final e = widget.existing;
    _date = TextEditingController(
        text: e?.paymentDate ?? d?.date.value ?? (d == null ? SwedishDates.iso(DateTime.now()) : ''));
    _partner = TextEditingController(text: e?.partner ?? d?.partner.value ?? '');
    _number = TextEditingController(text: e?.documentNumber ?? d?.documentNumber.value ?? '');
    _amount = TextEditingController(text: (e?.amount ?? d?.amount.value)?.toInput() ?? '');
    final vat = e != null ? (e.vat.isZero ? null : e.vat) : d?.vat.value;
    _vat = TextEditingController(text: vat?.toInput() ?? '');
    _rate = e?.vatRate ?? d?.vatRate;
    // Every field can be changed straight away; no "Redigera" step.
    _editing = true;
    if (_partner.text.isEmpty) {
      // Most owners have one partner: suggest the latest one.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final known = await AppScope.read(context).repo.knownPartners();
        if (mounted && known.isNotEmpty && _partner.text.isEmpty) setState(() => _partner.text = known.first);
      });
    }
  }

  void _changed([String? _]) => setState(() => _edited = true);

  Future<void> _save() async {
    if (!await requireLicense(context) || !mounted) return;
    final amount = Money.parse(_amount.text);
    final date = _date.text.trim();
    if (!SwedishDates.isValidIso(date)) {
      _blocked('Fyll i betalningsdatum innan du sparar.', _dateKey);
      return;
    }
    if (amount == null || amount.isZero) {
      _blocked('Fyll i betalt belopp innan du sparar.', _amountKey);
      return;
    }
    final vat = _vat.text.trim().isEmpty ? Money.zero : Money.parse(_vat.text);
    if (vat == null || (!vat.isZero && _rate == null)) {
      _blocked('Fyll i momsen och välj momssats, eller lämna momsen tom.', _vatKey);
      return;
    }
    final controller = AppScope.read(context);
    final sale = OnlineSale(
      id: widget.existing?.id,
      paymentDate: date,
      partner: _partner.text.trim(),
      documentNumber: _number.text.trim(),
      amount: amount,
      vat: vat,
      vatRate: vat.isZero ? null : _rate,
      meta: RecordMeta(
        source: widget.existing?.meta.source ?? (widget.scan == null ? RecordSource.manual : RecordSource.ocr),
        manuallyEdited: _edited,
        scanId: widget.existing?.meta.scanId,
      ),
    );
    final dupes = await controller.repo.findDuplicateOnlineSales(sale);
    if (dupes.isNotEmpty && mounted) {
      final choice = await duplicateDialog(context,
          title: 'Den här betalningen kan redan vara registrerad.',
          showExistingAvailable: false,
          lines: [
            for (final o in dupes) '${o.paymentDate} · ${o.partner} · ${o.amount.format()}',
          ]);
      if (choice != DuplicateChoice.saveAnyway || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      final scanId = await widget.scan?.persist(controller);
      await controller.repo.saveOnlineSale(scanId == null
          ? sale
          : OnlineSale(
              paymentDate: sale.paymentDate,
              partner: sale.partner,
              documentNumber: sale.documentNumber,
              amount: sale.amount,
              vat: sale.vat,
              vatRate: sale.vatRate,
              meta: sale.meta.copyWith(scanId: scanId),
            ));
      controller.dataChanged();
      if (!mounted) return;
      final fees = widget.draft?.feesInvoice;
      if (fees != null && widget.existing == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Försäljningen är sparad. Kontrollera nu partnerns faktura från samma dokument.')));
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => InvoiceReviewPage(draft: fees)));
        return;
      }
      showSaved(context, date: date);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Det gick inte att spara: $e')));
    }
  }

  void _blocked(String message, GlobalKey key) {
    setState(() => _editing = true);
    _form.currentState?.validate();
    showBlocked(context, message, key);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    Confidence? conf(Extracted<Object?>? e) =>
        widget.scan == null || e == null ? null : (e.hasValue ? e.confidence : Confidence.low);
    return ReviewScaffold(
      title: widget.existing != null ? 'Redigera onlineförsäljning' : 'Kontrollera uppgifterna',
      scan: widget.scan,
      editing: _editing,
      saving: _saving,
      onSave: _save,
      onRescan: widget.scan == null ? null : () => _rescan(context),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const DocTypeHeader(label: 'Onlineförsäljning'),
            if (d != null)
              for (final n in d.notes) NoteCard(n),
            PlainField(
                controller: _partner,
                label: 'Partner (t.ex. Foodora)',
                confidence: _partner.text.isEmpty ? null : conf(d?.partner),
                enabled: _editing,
                onChanged: _changed),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: _dateKey,
              child: DateField(
                  controller: _date,
                  label: 'Betalningsdatum',
                  confidence: conf(d?.date),
                  enabled: _editing,
                  onChanged: _changed),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: _amountKey,
              child: MoneyField(
                  controller: _amount,
                  label: 'Betalt belopp',
                  confidence: conf(d?.amount),
                  enabled: _editing,
                  onChanged: _changed),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: _vatKey,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: MoneyField(
                        controller: _vat,
                        label: 'Moms (om pappret visar den)',
                        confidence: d != null && d.vat.hasValue ? conf(d.vat) : null,
                        enabled: _editing,
                        onChanged: _changed),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<VatRate?>(
                      initialValue: _rate,
                      decoration: const InputDecoration(labelText: 'Momssats'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Ingen')),
                        for (final r in const [VatRate.six, VatRate.twelve, VatRate.twentyFive])
                          DropdownMenuItem(value: r, child: Text(r.label)),
                      ],
                      onChanged: _editing ? (v) => setState(() {
                            _rate = v;
                            _edited = true;
                          }) : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            PlainField(
                controller: _number,
                label: 'Dokumentnummer',
                confidence: d != null && d.documentNumber.hasValue ? conf(d.documentNumber) : null,
                enabled: _editing,
                onChanged: _changed),
            const SizedBox(height: 12),
            Text(
              'Beloppet läggs till månadens totala försäljning. Visar pappret moms på din försäljning '
              '(en självfaktura) räknas den som utgående moms. En utbetalning efter provision har ingen moms.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rescan(BuildContext context) async {
    final navigator = Navigator.of(context);
    await widget.scan?.discardImages();
    navigator.pop();
    await startScan(navigator.context, online: true);
  }
}

/// A month's payments behind the Onlineförsäljning row, to check, correct or
/// delete a single one.
class OnlinePaymentsPage extends StatelessWidget {
  final YearMonth month;
  const OnlinePaymentsPage({super.key, required this.month});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Onlineförsäljning, ${month.title.toLowerCase()}')),
        body: Reloading<List<OnlineSale>>(
          deps: month.title,
          loader: (c) => c.repo.onlineSalesBetween(month.firstDay, month.lastDay),
          builder: (context, list) {
            if (list.isEmpty) {
              return const EmptyState(icon: AppIcons.delivery, text: 'Ingen onlineförsäljning den här månaden.');
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final s in list)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text(s.partner.isEmpty ? 'Onlineförsäljning' : s.partner),
                      subtitle: Text(s.paymentDate),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(s.amount.format(), style: moneyStyle),
                        IconButton(
                          tooltip: 'Ta bort',
                          icon: const Icon(AppIcons.delete),
                          onPressed: () async {
                            final controller = AppScope.read(context);
                            final ok = await confirmDialog(context,
                                title: 'Ta bort betalningen?',
                                message: 'Beloppet tas bort från månadens försäljning.',
                                confirm: 'Ta bort');
                            if (!ok) return;
                            await controller.repo.deleteOnlineSale(s.id!);
                            controller.dataChanged();
                          },
                        ),
                      ]),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => OnlineReviewPage(existing: s))),
                    ),
                  ),
                const SizedBox(height: 8),
                Text('Summa ${Money.sum(list.map((s) => s.amount)).format()}',
                    textAlign: TextAlign.right, style: moneyStyle.copyWith(fontWeight: FontWeight.w500)),
              ],
            );
          },
        ),
      );
}
