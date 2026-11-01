import 'dart:io';

import 'package:flutter/material.dart';

import '../app_icons.dart';

import '../../app/app_controller.dart';
import '../../domain/dates.dart';
import '../../domain/invoice_parser.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/payment_detector.dart';
import '../../domain/text_patterns.dart';
import '../../domain/validation.dart';
import '../../domain/vat.dart';
import '../record_details.dart';
import '../scan/scan_context.dart';
import '../scan/scan_flow.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/fields.dart';
import 'ai_assist.dart';
import 'review_common.dart';

class _VatRow {
  VatRate rate;
  final TextEditingController amount;
  final Money? net;
  final Money? gross;
  bool calculated;
  _VatRow(this.rate, String amount, {this.net, this.gross, this.calculated = false})
      : amount = TextEditingController(text: amount);
}

/// "Kontrollera uppgifterna" for an invoice or receipt. Used after a scan,
/// for manual entry (no draft) and for editing a saved invoice.
class InvoiceReviewPage extends StatefulWidget {
  final InvoiceDraft? draft;
  final ScanContext? scan;
  final Invoice? existing;
  final bool fromAi;
  const InvoiceReviewPage({super.key, this.draft, this.scan, this.existing, this.fromAi = false});

  @override
  State<InvoiceReviewPage> createState() => _InvoiceReviewPageState();
}

class _InvoiceReviewPageState extends State<InvoiceReviewPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _date, _supplier, _number, _total, _vat, _due, _ocr;
  final List<_VatRow> _vatRows = [];
  late bool _editing;
  bool _edited = false;
  bool _saving = false;
  late bool _vatCalculated;
  List<VatRate> _rates = VatRuleSet.current.rates;

  /// Null until known: the user must say whether the document is paid.
  bool? _paid;
  String? _paidReason;
  PaymentKind _kind = PaymentKind.unknown;
  final _dateKey = GlobalKey();
  final _totalKey = GlobalKey();
  late final TextEditingController _paidDate, _bankgiro, _plusgiro;
  bool _rememberKind = true;
  bool _kindLoaded = false;

  /// Also true before a total is filled in, when the paper says Kreditnota.
  late bool _isCredit =
      (widget.draft?.isCredit ?? false) || (widget.existing?.total.isNegative ?? false);

  /// Flips the sign of total, VAT and VAT lines. The amounts themselves are
  /// unchanged; only whether they are added or subtracted.
  void _setCredit(bool credit) {
    void sign(TextEditingController c) {
      final v = Money.parse(c.text);
      if (v == null || v.isZero) return;
      c.text = (credit ? -v.abs() : v.abs()).toInput();
    }

    setState(() {
      _isCredit = credit;
      sign(_total);
      sign(_vat);
      for (final r in _vatRows) {
        sign(r.amount);
      }
      _edited = true;
    });
  }

  InvoiceDraft? get _d => widget.draft;
  bool get _manual => widget.draft == null && widget.existing == null;

  @override
  void initState() {
    super.initState();
    final d = _d;
    final e = widget.existing;
    String money(Money? m) => m?.toInput() ?? '';
    _date = TextEditingController(text: e?.invoiceDate ?? d?.date.value ?? (_manual ? SwedishDates.iso(DateTime.now()) : ''));
    _supplier = TextEditingController(text: e?.supplier ?? d?.supplier.value ?? '');
    _number = TextEditingController(text: e?.invoiceNumber ?? d?.invoiceNumber.value ?? '');
    _total = TextEditingController(text: money(e?.total ?? d?.total.value));
    _vat = TextEditingController(text: money(e?.vatTotal ?? d?.vatTotal.value));
    _due = TextEditingController(text: e?.dueDate ?? d?.dueDate.value ?? '');
    _ocr = TextEditingController(text: e?.ocrReference ?? d?.ocrReference.value ?? '');
    _vatCalculated = e?.vatCalculated ?? d?.vatCalculated ?? false;
    for (final l in e?.vatLines ?? d?.vatLines ?? const <InvoiceVatLine>[]) {
      _vatRows.add(_VatRow(l.rate, l.vat.toInput(), net: l.net, gross: l.gross, calculated: l.calculated));
    }
    _editing = widget.scan == null;

    final p = d?.payment;
    if (e != null) {
      _paid = e.paid;
    } else if (p != null && p.kind != PaymentKind.unknown) {
      _kind = p.kind;
      _paid = p.paid;
      _paidReason = _reasonFor(p);
    }
    _paidDate = TextEditingController(
        text: e?.paidDate ?? (_paid == true ? (d?.paidDate ?? d?.date.value ?? SwedishDates.iso(DateTime.now())) : ''));
    _bankgiro = TextEditingController(text: e?.bankgiro ?? d?.bankgiro.value ?? '');
    _plusgiro = TextEditingController(text: e?.plusgiro ?? d?.plusgiro.value ?? '');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = AppScope.read(context).repo;
    repo.vatRates().then((r) {
      if (mounted) setState(() => _rates = r);
    });
    // The earlier choice for this supplier decides only when the printed
    // signals are unsure; clear signals win, which also repairs a wrong memory.
    final p = _d?.payment;
    if (!_kindLoaded && widget.existing == null && _supplier.text.trim().isNotEmpty && !(p?.isCertain ?? false)) {
      _kindLoaded = true;
      repo.supplierPaymentKind(_supplier.text).then((kind) {
        if (!mounted || kind == null) return;
        setState(() {
          _kind = kind == 'kvitto' ? PaymentKind.kvitto : PaymentKind.faktura;
          _setPaid(kind == 'kvitto' || (p?.paid ?? false), edited: false);
          _paidReason = '${kind == 'kvitto' ? 'Kvitto' : 'Faktura'} enligt tidigare val för ${_supplier.text.trim()}';
        });
      });
    }
  }

  String _reasonFor(PaymentDetection p) {
    if (widget.draft?.isCredit ?? false) return 'Kreditnota: det finns inget att betala';
    if (p.reasons.contains(PaymentDetector.possibleStamp)) return 'Verkar ha en stämpel BETALD. Kontrollera.';
    if (p.reasons.contains(PaymentDetector.cashPayment)) return 'Betalningsvillkor: Kontant. Kontrollera.';
    if (p.kind == PaymentKind.kvitto) return 'Ser ut som ett kvitto (redan betalt)';
    return p.paid ? 'Faktura märkt som betald' : 'Ser ut som en faktura att betala';
  }

  void _setPaid(bool paid, {bool edited = true}) {
    _paid = paid;
    if (paid && _paidDate.text.isEmpty) {
      _paidDate.text = SwedishDates.isValidIso(_date.text.trim()) ? _date.text.trim() : SwedishDates.iso(DateTime.now());
    }
    if (edited) {
      _edited = true;
      _paidReason = null;
    }
  }

  /// What the supplier sends. Paying a faktura does not make it a kvitto.
  PaymentKind get _effectiveKind => _kind != PaymentKind.unknown
      ? _kind
      : _paid == true
          ? PaymentKind.kvitto
          : PaymentKind.faktura;

  /// Why the offline reading is not good enough; empty when it is.
  late final List<String> _aiReasons = _computeAiReasons();

  List<String> _computeAiReasons() {
    final d = _d;
    if (d == null) return const [];
    final out = <String>[
      if (!d.total.hasValue) 'Summan hittades inte' else if (d.total.confidence == Confidence.low) 'Summan är osäker',
      if (!d.date.hasValue) 'Datum hittades inte',
      if (!d.vatTotal.hasValue) 'Momsen hittades inte',
    ];
    if (d.total.hasValue) {
      final draftInvoice = Invoice(
        invoiceDate: d.date.value ?? '2000-01-01',
        total: d.total.value!,
        vatTotal: d.vatTotal.value ?? Money.zero,
        vatLines: d.vatLines,
        meta: const RecordMeta(source: RecordSource.ocr),
      );
      out.addAll(const AccountingValidationEngine()
          .validateInvoice(draftInvoice, net: d.net)
          .where((r) => !r.isOk)
          .map((r) => r.message));
    }
    return out;
  }

  void _changed([String? _]) => setState(() => _edited = true);

  Invoice? _build() {
    // On a kreditnota every amount counts as minus, also one typed without it.
    Money signed(Money m) => _isCredit ? -m.abs() : m;
    final parsedTotal = Money.parse(_total.text);
    if (parsedTotal == null || !SwedishDates.isValidIso(_date.text.trim())) return null;
    final total = signed(parsedTotal);
    final parsedVat = _vat.text.trim().isEmpty ? Money.zero : Money.parse(_vat.text);
    if (parsedVat == null) return null;
    final vat = signed(parsedVat);
    final lines = <InvoiceVatLine>[];
    for (final r in _vatRows) {
      final v = Money.parse(r.amount.text);
      if (v == null) return null;
      lines.add(InvoiceVatLine(rate: r.rate, vat: signed(v), net: r.net, gross: r.gross, calculated: r.calculated));
    }
    final source = widget.existing?.meta.source ?? (widget.fromAi ? RecordSource.ai : widget.scan == null ? RecordSource.manual : RecordSource.ocr);
    return Invoice(
      id: widget.existing?.id,
      invoiceDate: _date.text.trim(),
      supplier: _supplier.text.trim(),
      invoiceNumber: _number.text.trim(),
      total: total,
      vatTotal: vat,
      vatCalculated: _vatCalculated,
      dueDate: SwedishDates.isValidIso(_due.text.trim()) ? _due.text.trim() : null,
      ocrReference: _ocr.text.trim(),
      vatLines: lines,
      meta: RecordMeta(
        source: source,
        manuallyEdited: _edited || (widget.existing?.meta.manuallyEdited ?? false),
        scanId: widget.existing?.meta.scanId,
      ),
      paid: _paid ?? false,
      paidDate: _paid == true && SwedishDates.isValidIso(_paidDate.text.trim()) ? _paidDate.text.trim() : null,
      bankgiro: _bankgiro.text.trim(),
      plusgiro: _plusgiro.text.trim(),
    );
  }

  Future<void> _save() async {
    final valid = _form.currentState?.validate() ?? false;
    if (!valid) {
      setState(() => _editing = true);
      if (!SwedishDates.isValidIso(_date.text.trim())) {
        showBlocked(context, 'Fyll i datum innan du sparar.', _dateKey);
      } else if (Money.parse(_total.text) == null) {
        showBlocked(context, 'Fyll i summan innan du sparar.', _totalKey);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Rätta det som är rödmarkerat innan du sparar.')));
      }
      return;
    }
    final inv = _build();
    if (inv == null) return;
    if (_paid == null) {
      setState(() => _editing = true);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Välj om dokumentet redan är betalt (kvitto) eller ska betalas (faktura).')));
      return;
    }
    final controller = AppScope.read(context);
    final checks =const AccountingValidationEngine().validateInvoice(inv, net: _d?.net);
    final problems = checks.where((c) => !c.isOk).toList();
    if (problems.isNotEmpty) {
      final ok = await confirmDialog(context,
          title: 'Det finns varningar',
          message: '${problems.map((p) => '• ${p.message}').join('\n')}\n\nVill du spara ändå? Uppgifterna sparas precis som de står.',
          confirm: 'Spara ändå');
      if (!ok || !mounted) return;
    }
    final dupes = await controller.repo.findDuplicateInvoices(inv);
    if (dupes.isNotEmpty && mounted) {
      final choice = await duplicateDialog(context,
          title: 'Den här fakturan kan redan vara registrerad.',
          lines: [
            for (final d in dupes)
              '${d.invoiceDate} · ${d.supplier.isEmpty ? 'Faktura' : d.supplier}'
                  '${d.invoiceNumber.isEmpty ? '' : ' · nr ${d.invoiceNumber}'} · ${d.total.format()}',
          ]);
      if (!mounted) return;
      if (choice == DuplicateChoice.showExisting) {
        await openRecord(context, 'invoice', dupes.first.id!);
        return;
      }
      if (choice != DuplicateChoice.saveAnyway) return;
    }
    setState(() => _saving = true);
    try {
      final scanId = await widget.scan?.persist(controller);
      final toSave = scanId == null ? inv : inv.copyWith(meta: inv.meta.copyWith(scanId: scanId));
      await controller.repo.saveInvoice(toSave);
      if (!toSave.paid && toSave.dueDate != null) await controller.reminders?.requestPermission();
      if (_rememberKind && inv.supplier.isNotEmpty && !inv.total.isNegative) {
        await controller.repo
            .rememberSupplierPaymentKind(inv.supplier, _effectiveKind == PaymentKind.kvitto ? 'kvitto' : 'faktura');
      }
      controller.dataChanged();
      if (!mounted) return;
      showSaved(context, date: inv.invoiceDate);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Det gick inte att spara: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final inv = _build();
    final checks = inv == null ? const <ValidationResult>[] : const AccountingValidationEngine().validateInvoice(inv, net: d?.net);
    Confidence? conf(Extracted<Object?>? e) =>
        widget.scan == null || e == null ? null : (e.hasValue ? e.confidence : Confidence.low);
    // Optional fields that are simply not on the paper are not uncertain.
    Confidence? optional(Extracted<Object?>? e) => e != null && e.hasValue ? conf(e) : null;
    final linesSum = Money.sum(_vatRows.map((r) => Money.parse(r.amount.text) ?? Money.zero));
    final vatValue = Money.parse(_vat.text);

    return ReviewScaffold(
      title: widget.existing != null ? 'Redigera faktura' : 'Kontrollera uppgifterna',
      scan: widget.scan,
      editing: _editing,
      saving: _saving,
      onSave: _save,
      onEdit: () => setState(() => _editing = !_editing),
      onRescan: widget.scan == null ? null : () => _rescan(context),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DocTypeHeader(
                label: _isCredit
                    ? 'Kreditnota'
                    : _effectiveKind == PaymentKind.kvitto && _paid == true
                        ? 'Kvitto'
                        : 'Faktura'),
            if (widget.scan != null && !widget.fromAi) AiOfferCard(scan: widget.scan!, reasons: _aiReasons),
            if (d != null)
              for (final n in d.notes) NoteCard(n),
            KeyedSubtree(
              key: _dateKey,
              child: DateField(controller: _date, label: 'Datum', confidence: conf(d?.date), enabled: _editing, onChanged: _changed),
            ),
            if (d?.date.note != null) Text(d!.date.note!, style: Theme.of(context).textTheme.bodySmall),
            if (d != null && d.dateOptions.length > 1)
              Wrap(
                spacing: 6,
                children: [
                  for (final o in d.dateOptions)
                    ActionChip(
                      label: Text('${o.label}: ${o.date}'),
                      onPressed: !_editing
                          ? null
                          : () => setState(() {
                                _date.text = o.date;
                                _edited = true;
                              }),
                    ),
                ],
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Kreditnota'),
              subtitle: const Text('Beloppen blir minus och dras av från utgifterna'),
              value: _isCredit,
              onChanged: !_editing ? null : _setCredit,
            ),
            const SizedBox(height: 4),
            PlainField(controller: _supplier, label: 'Leverantör', confidence: conf(d?.supplier), enabled: _editing, onChanged: _changed),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: _totalKey,
              child: MoneyField(controller: _total, label: 'Summa (att betala)', confidence: conf(d?.total), enabled: _editing, onChanged: _changed),
            ),
            if (d != null && d.totalCandidates.any((c) => c.value != d.total.value?.abs())) _alternatives(d),
            const SizedBox(height: 12),
            MoneyField(
              controller: _vat,
              label: _vatCalculated ? 'Moms (beräknad)' : 'Moms',
              confidence: conf(d?.vatTotal),
              enabled: _editing,
              required: false,
              onChanged: (v) {
                _vatCalculated = false;
                _changed();
              },
            ),
            const SizedBox(height: 8),
            _vatSection(linesSum, vatValue),
            const SizedBox(height: 12),
            PlainField(controller: _number, label: 'Fakturanummer', confidence: optional(d?.invoiceNumber), enabled: _editing, onChanged: _changed),
            const SizedBox(height: 12),
            DateField(controller: _due, label: 'Förfallodatum', confidence: optional(d?.dueDate), enabled: _editing, required: false, onChanged: _changed),
            const SizedBox(height: 12),
            PlainField(
                controller: _ocr,
                label: 'OCR-nummer',
                confidence: optional(d?.ocrReference),
                enabled: _editing,
                keyboardType: TextInputType.number,
                onChanged: _changed),
            const SizedBox(height: 16),
            _paymentSection(),
            const SizedBox(height: 16),
            Text('Kontroll', style: Theme.of(context).textTheme.titleSmall),
            if (inv == null)
              const Text('Fyll i datum och summa för att kontrollera beloppen.')
            else
              ValidationList(checks),
          ],
        ),
      ),
    );
  }

  /// Kvitto (already paid) or faktura (to pay). Pre-filled from the printed
  /// signals or the supplier's earlier choice; the user always confirms.
  Widget _paymentSection() {
    final t = Theme.of(context).textTheme;
    final paid = _paid;
    final supplier = _supplier.text.trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Betalning', style: t.titleSmall),
            if (paid == null) ...[
              const SizedBox(height: 6),
              const Text('Är dokumentet redan betalt?', style: TextStyle(color: AppTheme.warning)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => setState(() {
                        _kind = PaymentKind.kvitto;
                        _setPaid(true);
                      }),
                      child: const Text('Betald (kvitto)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => setState(() {
                        _kind = PaymentKind.faktura;
                        _setPaid(false);
                      }),
                      child: const Text('Obetald (faktura)'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Redan betald'),
                subtitle: _paidReason == null ? null : Text(_paidReason!),
                value: paid,
                onChanged: !_editing ? null : (v) => setState(() => _setPaid(v)),
              ),
              if (paid)
                DateField(
                    controller: _paidDate,
                    label: 'Betalningsdatum',
                    enabled: _editing,
                    required: false,
                    onChanged: _changed)
              else ...[
                if (!SwedishDates.isValidIso(_due.text.trim()))
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('Fyll i förfallodatum ovan för att få en påminnelse.',
                        style: TextStyle(color: AppTheme.warning)),
                  ),
                PlainField(
                    controller: _bankgiro,
                    label: 'Bankgiro',
                    enabled: _editing,
                    keyboardType: TextInputType.number,
                    onChanged: _changed),
                const SizedBox(height: 8),
                PlainField(
                    controller: _plusgiro,
                    label: 'Plusgiro',
                    enabled: _editing,
                    keyboardType: TextInputType.number,
                    onChanged: _changed),
              ],
            ],
            if (widget.existing == null && supplier.isNotEmpty && paid != null)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _rememberKind,
                title: Text('Kom ihåg: $supplier skickar ${_effectiveKind == PaymentKind.kvitto ? 'kvitton' : 'fakturor'}'),
                onChanged: (v) => setState(() => _rememberKind = v ?? false),
              ),
          ],
        ),
      ),
    );
  }

  Widget _alternatives(InvoiceDraft d) {
    final seen = <Money>{if (d.total.value != null) d.total.value!.abs()};
    final options = d.totalCandidates.where((c) => seen.add(c.value)).take(4).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Andra möjliga belopp:'),
          for (final c in options)
            ActionChip(
              label: Text('${c.value.format()} (${c.row.length > 24 ? '${c.row.substring(0, 24)}…' : c.row})'),
              onPressed: !_editing
                  ? null
                  : () => setState(() {
                        _total.text = c.value.toInput();
                        _edited = true;
                      }),
            ),
        ],
      ),
    );
  }

  Widget _vatSection(Money linesSum, Money? vatValue) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Moms per momssats', style: Theme.of(context).textTheme.titleSmall),
            if (_vatRows.isEmpty) const Text('Ingen uppdelning. Lägg till om fakturan visar moms per momssats.'),
            for (final r in _vatRows)
              Row(
                children: [
                  DropdownButton<int>(
                    value: r.rate.basisPoints,
                    items: [
                      for (final rate in {..._rates, r.rate}.toList()..sort())
                        DropdownMenuItem(value: rate.basisPoints, child: Text(rate.label)),
                    ],
                    onChanged: !_editing
                        ? null
                        : (v) => setState(() {
                              r.rate = VatRate(v!);
                              _edited = true;
                            }),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: r.amount,
                      enabled: _editing,
                      textAlign: TextAlign.right,
                      style: moneyStyle,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: r.calculated ? 'Moms (beräknad)' : 'Moms',
                        suffixText: 'kr',
                        isDense: true,
                      ),
                      validator: (v) => Money.parse(v ?? '') == null ? 'Ange ett belopp' : null,
                      onChanged: (_) {
                        r.calculated = false;
                        _changed();
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: 'Ta bort raden',
                    icon: const Icon(AppIcons.close),
                    onPressed: !_editing
                        ? null
                        : () => setState(() {
                              _vatRows.remove(r);
                              _edited = true;
                            }),
                  ),
                ],
              ),
            if (_editing)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(AppIcons.add),
                  label: const Text('Lägg till momssats'),
                  onPressed: () => setState(() {
                    _vatRows.add(_VatRow(VatRate.twentyFive, ''));
                    _edited = true;
                  }),
                ),
              ),
            if (_vatRows.isNotEmpty && vatValue != linesSum) ...[
              Text('Summan av momsraderna är ${linesSum.format()}.',
                  style: const TextStyle(color: AppTheme.warning)),
              if (_editing)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => setState(() {
                      _vat.text = linesSum.toInput();
                      _vatCalculated = false;
                      _edited = true;
                    }),
                    child: const Text('Använd summan som total moms'),
                  ),
                ),
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

/// Small preview of a stored image used by the details pages.
class StoredImage extends StatelessWidget {
  final String path;
  const StoredImage(this.path, {super.key});

  @override
  Widget build(BuildContext context) => File(path).existsSync()
      ? Image.file(File(path), fit: BoxFit.contain)
      : const Text('Bilden finns inte längre.');
}
