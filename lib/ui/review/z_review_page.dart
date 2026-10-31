import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../data/repository.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/text_patterns.dart';
import '../../domain/validation.dart';
import '../../domain/z_report_parser.dart';
import '../record_details.dart';
import '../scan/scan_context.dart';
import '../scan/scan_flow.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/fields.dart';
import 'review_common.dart';

/// One editable row: a line from the report (or a category for manual entry)
/// and the category it counts towards. A null category means "not counted".
class _Row {
  final String label;
  final bool fromReport;
  final TextEditingController amount;
  int? categoryId;
  final int? suggestedId;
  final MatchKind match;
  final String? warning;
  bool remember = true;
  bool userAssigned = false;

  _Row({
    required this.label,
    required this.fromReport,
    required String amount,
    this.categoryId,
    this.suggestedId,
    this.match = MatchKind.none,
    this.warning,
  }) : amount = TextEditingController(text: amount);
}

/// "Kontrollera uppgifterna" for a Z-report: business date, category rows,
/// reported daily total and the reconciliation. The app never changes an
/// amount to make the totals agree.
class ZReviewPage extends StatefulWidget {
  final ZReportDraft? draft;
  final ScanContext? scan;
  final DailySales? existing;
  const ZReviewPage({super.key, this.draft, this.scan, this.existing});

  @override
  State<ZReviewPage> createState() => _ZReviewPageState();
}

class _ZReviewPageState extends State<ZReviewPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _date, _zNumber, _reported, _note;
  List<Category>? _categories;
  final List<_Row> _rows = [];
  late bool _editing;
  bool _edited = false;
  bool _saving = false;

  ZReportDraft? get _d => widget.draft;

  @override
  void initState() {
    super.initState();
    final d = _d;
    final e = widget.existing;
    _date = TextEditingController(
        text: e?.businessDate ?? d?.date.value ?? (d == null ? SwedishDates.iso(DateTime.now()) : ''));
    _zNumber = TextEditingController(text: e?.zNumber ?? d?.zNumber.value ?? '');
    _reported = TextEditingController(text: (e?.reportedTotal ?? d?.total.value)?.toInput() ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _editing = widget.scan == null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_categories == null) _load();
  }

  Future<void> _load() async {
    final cats = await AppScope.read(context).repo.categories();
    if (!mounted) return;
    final d = _d;
    final e = widget.existing;
    setState(() {
      _categories = cats;
      if (e != null) {
        for (final i in e.items) {
          _rows.add(_Row(
              label: i.sourceLabel ?? i.categoryName,
              fromReport: false,
              amount: i.amount.toInput(),
              categoryId: cats.any((c) => c.id == i.categoryId) ? i.categoryId : null));
        }
      } else if (d != null) {
        for (final l in d.lines) {
          _rows.add(_Row(
            label: l.label,
            fromReport: true,
            amount: l.amount.toInput(),
            categoryId: l.categoryId,
            suggestedId: l.suggestedCategoryId,
            match: l.match,
            warning: l.warning,
          ));
        }
      } else {
        for (final c in cats) {
          _rows.add(_Row(label: c.name, fromReport: false, amount: '', categoryId: c.id));
        }
      }
    });
  }

  void _changed([String? _]) => setState(() => _edited = true);

  Category? _cat(int? id) => _categories?.where((c) => c.id == id).firstOrNull;

  List<SalesItem> _items() {
    final byCat = <int, (Money, List<String>)>{};
    for (final r in _rows) {
      final id = r.categoryId;
      final v = Money.parse(r.amount.text);
      if (id == null || v == null) continue;
      final prev = byCat[id];
      byCat[id] = ((prev?.$1 ?? Money.zero) + v, [...?prev?.$2, if (r.fromReport) r.label]);
    }
    final cats = _categories ?? const <Category>[];
    return [
      for (final c in cats)
        if (byCat.containsKey(c.id))
          SalesItem(
            categoryId: c.id,
            categoryName: c.name,
            vat: c.vat,
            amount: byCat[c.id]!.$1,
            sourceLabel: byCat[c.id]!.$2.isEmpty ? null : byCat[c.id]!.$2.join(', '),
          ),
    ];
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) {
      setState(() => _editing = true);
      return;
    }
    final reported = Money.parse(_reported.text);
    if (reported == null) return;
    final controller = AppScope.read(context);
    final items = _items();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Koppla minst en rad till en kategori innan du sparar.')));
      return;
    }
    final day = DailySales(
      id: widget.existing?.id,
      businessDate: _date.text.trim(),
      zNumber: _zNumber.text.trim().isEmpty ? null : _zNumber.text.trim(),
      reportedTotal: reported,
      items: items,
      note: _note.text.trim(),
      meta: RecordMeta(
        source: widget.existing?.meta.source ?? (widget.scan == null ? RecordSource.manual : RecordSource.ocr),
        manuallyEdited: _edited || (widget.existing?.meta.manuallyEdited ?? false),
        scanId: widget.existing?.meta.scanId,
      ),
    );
    if (!day.difference.isZero) {
      final ok = await confirmDialog(context,
          title: 'Försäljningsbeloppen stämmer inte',
          message: 'Detaljerade poster: ${day.detailedTotal.format()}\n'
              'Rapporterad dagsförsäljning: ${day.reportedTotal.format()}\n'
              'Skillnad: ${day.difference.format()}\n\n'
              'Kontrollera beloppen. Vill du spara ändå? Skillnaden markeras i rapporterna.',
          confirm: 'Spara ändå');
      if (!ok || !mounted) return;
    }
    final dupes = await controller.repo.findDuplicateDailySales(day);
    if (dupes.isNotEmpty && mounted) {
      final choice = await duplicateDialog(context,
          title: 'Den här Z-rapporten kan redan vara registrerad.',
          lines: [
            for (final d in dupes)
              '${d.businessDate}${(d.zNumber ?? '').isEmpty ? '' : ' · Z-nr ${d.zNumber}'} · ${d.reportedTotal.format()}',
          ]);
      if (!mounted) return;
      if (choice == DuplicateChoice.showExisting) {
        await openRecord(context, 'z', dupes.first.id!);
        return;
      }
      if (choice != DuplicateChoice.saveAnyway) return;
    }
    setState(() => _saving = true);
    try {
      for (final r in _rows) {
        final c = _cat(r.categoryId);
        if (r.fromReport && r.userAssigned && r.remember && c != null &&
            Repository.normalizeLabel(r.label) != Repository.normalizeLabel(c.name)) {
          await controller.repo.rememberAlias(r.label, c.id!);
        }
      }
      final scanId = await widget.scan?.persist(controller);
      await controller.repo.saveDailySales(scanId == null
          ? day
          : DailySales(
              businessDate: day.businessDate,
              zNumber: day.zNumber,
              reportedTotal: day.reportedTotal,
              items: day.items,
              note: day.note,
              meta: day.meta.copyWith(scanId: scanId),
            ));
      controller.dataChanged();
      if (!mounted) return;
      showSaved(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Det gick inte att spara: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = _categories;
    final d = _d;
    Confidence? conf(Extracted<Object?>? e) =>
        widget.scan == null || e == null ? null : (e.hasValue ? e.confidence : Confidence.low);
    final items = _items();
    final detailed = Money.sum(items.map((i) => i.amount));
    final reported = Money.parse(_reported.text);
    final check = reported == null
        ? null
        : const AccountingValidationEngine().reconcileZReport(items.map((i) => i.amount), reported);
    final ignored = _rows.where((r) => r.categoryId == null && (Money.parse(r.amount.text)?.ore ?? 0) != 0).length;

    return ReviewScaffold(
      title: widget.existing != null ? 'Redigera Z-rapport' : 'Kontrollera uppgifterna',
      scan: widget.scan,
      editing: _editing,
      saving: _saving,
      onSave: _save,
      onEdit: () => setState(() => _editing = !_editing),
      onRescan: widget.scan == null ? null : () => _rescan(context),
      child: cats == null
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const DocTypeHeader(label: 'Z-rapport'),
                  if (cats.isEmpty)
                    const NoteCard('Du har inga försäljningskategorier. Lägg till dem under Inställningar → Försäljningskategorier.'),
                  if (d != null)
                    for (final n in d.notes) NoteCard(n),
                  DateField(controller: _date, label: 'Datum (försäljningsdag)', confidence: conf(d?.date), enabled: _editing, onChanged: _changed),
                  if (d != null && d.otherDates.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(d.date.note ?? 'Andra datum på rapporten:'),
                        for (final o in d.otherDates)
                          ActionChip(
                            label: Text(o),
                            onPressed: !_editing ? null : () => setState(() {
                              _date.text = o;
                              _edited = true;
                            }),
                          ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  PlainField(controller: _zNumber, label: 'Z-nummer', confidence: conf(d?.zNumber), enabled: _editing, onChanged: _changed),
                  const SizedBox(height: 16),
                  Text('Försäljning per kategori', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  for (final r in _rows) _rowCard(r, cats),
                  if (_editing)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Lägg till rad'),
                        onPressed: cats.isEmpty
                            ? null
                            : () => setState(() {
                                  _rows.add(_Row(label: cats.first.name, fromReport: false, amount: '', categoryId: cats.first.id));
                                  _edited = true;
                                }),
                      ),
                    ),
                  const SizedBox(height: 12),
                  MoneyField(controller: _reported, label: 'Dagsförsäljning (enligt rapporten)', confidence: conf(d?.total), enabled: _editing, onChanged: _changed),
                  const SizedBox(height: 12),
                  _summary(detailed, reported, check, ignored),
                  const SizedBox(height: 12),
                  _vatSummary(items),
                  const SizedBox(height: 12),
                  PlainField(controller: _note, label: 'Anteckning (valfri)', enabled: _editing, onChanged: _changed),
                ],
              ),
            ),
    );
  }

  Widget _rowCard(_Row r, List<Category> cats) {
    final suggested = _cat(r.suggestedId);
    final assigned = _cat(r.categoryId);
    final needsConfirm = r.categoryId == null && suggested != null && !r.userAssigned;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: needsConfirm ? AppTheme.warning.withValues(alpha: 0.08) : null,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.fromReport ? 'På rapporten: ${r.label}' : (assigned?.name ?? r.label),
                          style: Theme.of(context).textTheme.bodyMedium),
                      if (r.match == MatchKind.exact || r.match == MatchKind.remembered)
                        Text(r.match == MatchKind.exact ? 'Samma namn som kategorin' : 'Kopplingen är sparad sedan tidigare',
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: TextFormField(
                    controller: r.amount,
                    enabled: _editing,
                    textAlign: TextAlign.right,
                    style: moneyStyle,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(suffixText: 'kr', isDense: true),
                    validator: (v) => (v ?? '').trim().isEmpty || Money.parse(v!) != null ? null : 'Fel belopp',
                    onChanged: _changed,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Text('Räknas som: '),
                Expanded(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: r.categoryId ?? -1,
                    items: [
                      for (final c in cats) DropdownMenuItem(value: c.id, child: Text('${c.name} (${c.vat.label})')),
                      const DropdownMenuItem(value: -1, child: Text('Räknas inte med')),
                    ],
                    onChanged: !_editing && !needsConfirm
                        ? null
                        : (v) => setState(() {
                              r.categoryId = v == -1 ? null : v;
                              r.userAssigned = true;
                              _edited = true;
                            }),
                  ),
                ),
                if (_editing && !r.fromReport)
                  IconButton(
                    tooltip: 'Ta bort raden',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _rows.remove(r);
                      _edited = true;
                    }),
                  ),
              ],
            ),
            if (needsConfirm) ...[
              Text('Vi hittade en möjlig matchning: ${suggested.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
              if (r.warning != null) Text(r.warning!, style: const TextStyle(color: AppTheme.warning)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() {
                    r.categoryId = suggested.id;
                    r.userAssigned = true;
                    _edited = true;
                  }),
                  child: Text('Använd ${suggested.name}'),
                ),
              ),
            ] else if (r.warning != null)
              Text(r.warning!, style: const TextStyle(color: AppTheme.warning)),
            if (r.fromReport && r.userAssigned && assigned != null &&
                Repository.normalizeLabel(r.label) != Repository.normalizeLabel(assigned.name))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: r.remember,
                title: Text('Kom ihåg: "${r.label}" räknas som ${assigned.name}'),
                onChanged: (v) => setState(() => r.remember = v ?? false),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summary(Money detailed, Money? reported, ValidationResult? check, int ignored) {
    final ok = check?.isOk ?? false;
    return Card(
      color: check == null ? null : (ok ? AppTheme.ok : AppTheme.warning).withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _line('Dagsförsäljning', reported?.format() ?? '–'),
            _line('Beräknad detaljerad summa', detailed.format()),
            _line('Skillnad', reported == null ? '–' : (detailed - reported).format()),
            const SizedBox(height: 6),
            if (check != null)
              Text(ok ? 'Uppgifterna stämmer' : 'Varning: differens ${(detailed - reported!).format()}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: ok ? AppTheme.ok : AppTheme.warning)),
            if (check != null) Text(check.message),
            if (ignored > 0)
              Text('$ignored ${ignored == 1 ? 'rad räknas' : 'rader räknas'} inte med.',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _vatSummary(List<SalesItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    final vat = Money.sum(items.map((i) => i.vatAmount));
    final total = Money.sum(items.map((i) => i.amount));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Beräknad moms', style: Theme.of(context).textTheme.titleSmall),
            for (final i in items) _line('${i.categoryName} ${i.vat.label}', i.vatAmount.format()),
            const Divider(),
            _line('Försäljning inkl. moms', total.format()),
            _line('Moms', vat.format()),
            _line('Försäljning exkl. moms', (total - vat).format()),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [Expanded(child: Text(label)), Text(value, style: moneyStyle)]),
      );

  Future<void> _rescan(BuildContext context) async {
    final navigator = Navigator.of(context);
    await widget.scan?.discardImages();
    navigator.pop();
    await startScan(navigator.context);
  }
}
