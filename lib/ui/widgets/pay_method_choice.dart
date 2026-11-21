import 'package:flutter/material.dart';

import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/pay_method.dart';
import '../app_icons.dart';
import '../theme.dart';
import 'blur_overlay.dart';

/// "Betalades med": Bank / kort, Kontant or Privat. Yellow ("Kontrollera") until the
/// owner has tapped a choice, as Kostnadstyp is: what the receipt says is only a
/// suggestion, and a card can be the company's or the owner's own.
class PayMethodChoice extends StatelessWidget {
  final PayMethod value;

  /// False while [value] is only the default or a suggestion from the paper.
  final bool confirmed;

  /// Why the paper suggests [value], e.g. 'kvittot säger "Kontant" och visar växel'.
  final String? suggestion;
  final CompanyForm? form;
  final ValueChanged<PayMethod> onChanged;

  /// With [total] and [onSplit] a link "Dela upp betalningen" is shown: part cash, part
  /// card. [split] is the parts so far in absolute kronor (two or more while split); the
  /// last one is always the rest, so they add up to [total].
  final Money? total;
  final List<PaymentPart> split;
  final ValueChanged<List<PaymentPart>>? onSplit;
  const PayMethodChoice({
    super.key,
    required this.value,
    required this.onChanged,
    this.confirmed = true,
    this.suggestion,
    this.form,
    this.total,
    this.split = const [],
    this.onSplit,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final unsure = !confirmed;
    final total = this.total?.abs();
    if (total != null && onSplit != null && split.length > 1) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.hairline),
        ),
        child: _SplitRows(
          total: total,
          parts: split,
          onChanged: onSplit!,
          onUndo: () => onSplit!(const []),
        ),
      );
    }
    final hint = unsure
        ? (suggestion != null
            ? 'Förslag: $suggestion.'
            : 'Välj det som stämmer. Kortet kan vara företagets eller ditt eget.')
        : value.explain(form);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: unsure ? AppTheme.unsureTint : AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: unsure ? AppTheme.unsure : AppTheme.hairline, width: unsure ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (unsure) ...[Icon(AppIcons.warning, size: 16, color: AppTheme.unsure), const SizedBox(width: 6)],
          Text(unsure ? 'Kontrollera: hur betalade du?' : 'Betalades med',
              style: t.bodyMedium?.copyWith(color: unsure ? AppTheme.unsure : null, fontWeight: unsure ? FontWeight.w600 : null)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          for (final (i, m) in PayMethod.values.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Semantics(
                button: true,
                selected: m == value,
                label: m.label,
                child: Material(
                  color: m == value ? AppTheme.seed : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: m == value ? AppTheme.seed : AppTheme.fieldBorder, width: 1.5),
                  ),
                  child: InkWell(
                    customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onTap: () => onChanged(m),
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      child: Text(m.label,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: m == value ? Colors.white : AppTheme.muted)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        Text(hint, style: t.bodySmall?.copyWith(color: unsure ? AppTheme.unsure : AppTheme.muted)),
        if (total != null && !total.isZero && onSplit != null)
          InkWell(
            onTap: () => onSplit!([
              PaymentPart(PayMethod.cash, Money.zero),
              PaymentPart(value == PayMethod.cash ? PayMethod.bank : value, total),
            ]),
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(AppIcons.swap, size: 18, color: AppTheme.accounting),
                const SizedBox(width: 6),
                Text('Dela upp betalningen',
                    style: TextStyle(color: AppTheme.accounting, fontWeight: FontWeight.w600, fontSize: 13.5)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// The rows of a split payment: a method and an amount each, the last row always the rest.
class _SplitRows extends StatefulWidget {
  final Money total;
  final List<PaymentPart> parts;
  final ValueChanged<List<PaymentPart>> onChanged;
  final VoidCallback onUndo;
  const _SplitRows({required this.total, required this.parts, required this.onChanged, required this.onUndo});

  @override
  State<_SplitRows> createState() => _SplitRowsState();
}

class _SplitRowsState extends State<_SplitRows> {
  late final List<PayMethod> _methods = [for (final p in widget.parts) p.method];
  late final List<TextEditingController> _c = [
    for (final p in widget.parts) TextEditingController(text: p.amount.isZero ? '' : p.amount.toInput()),
  ];

  @override
  void dispose() {
    for (final c in _c) {
      c.dispose();
    }
    super.dispose();
  }

  Money _typed(int i) => Money.parse(_c[i].text)?.abs() ?? Money.zero;

  /// The rest after every row but the last.
  Money get _rest {
    var sum = Money.zero;
    for (var i = 0; i < _c.length - 1; i++) {
      sum += _typed(i);
    }
    return widget.total - sum;
  }

  void _emit() {
    final last = _c.length - 1;
    widget.onChanged([
      for (var i = 0; i < _c.length; i++) PaymentPart(_methods[i], i == last ? _rest : _typed(i)),
    ]);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final rest = _rest;
    final last = _c.length - 1;
    final tooMuch = rest.isNegative;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Betalades med (uppdelat)', style: t.bodyMedium),
      for (var i = 0; i < _c.length; i++)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Expanded(
              child: PopupMenuButton<PayMethod>(
                tooltip: 'Betalsätt',
                onSelected: (m) {
                  _methods[i] = m;
                  _emit();
                },
                itemBuilder: (_) => [for (final m in PayMethod.values) PopupMenuItem(value: m, child: Text(m.label))],
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.fieldBorder, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Expanded(child: Text(_methods[i].label, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Icon(AppIcons.expand, size: 18, color: AppTheme.muted),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 116,
              height: 44,
              child: i == last
                  ? Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.background,
                        border: Border.all(color: tooMuch ? AppTheme.danger : AppTheme.fieldBorder, width: 1.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(rest.format(unit: false),
                          style: t.titleSmall?.copyWith(color: tooMuch ? AppTheme.danger : AppTheme.muted)),
                    )
                  : TextField(
                      controller: _c[i],
                      textAlign: TextAlign.end,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12), hintText: '0,00'),
                      onChanged: (_) => _emit(),
                    ),
            ),
            SizedBox(
              width: 36,
              child: IconButton(
                tooltip: 'Ta bort raden',
                icon: Icon(AppIcons.close, size: 18, color: AppTheme.muted),
                onPressed: () {
                  if (_c.length <= 2) {
                    widget.onUndo();
                    return;
                  }
                  _methods.removeAt(i);
                  _c.removeAt(i).dispose();
                  _emit();
                },
              ),
            ),
          ]),
        ),
      TextButton.icon(
        onPressed: () {
          _methods.insert(_c.length - 1, PayMethod.bank);
          _c.insert(_c.length - 1, TextEditingController());
          _emit();
        },
        icon: const Icon(AppIcons.add, size: 18),
        label: const Text('Lägg till rad'),
      ),
      Row(children: [
        Expanded(child: Text('Summa', style: t.bodyMedium)),
        Text(tooMuch ? 'Beloppen är ${(-rest).format()} för stora' : '${widget.total.format()} stämmer',
            style: t.titleSmall?.copyWith(color: tooMuch ? AppTheme.danger : AppTheme.seed)),
      ]),
      const SizedBox(height: 4),
      Text('Sista raden fylls i med resten. Varje del bokförs på sitt eget konto.',
          style: t.bodySmall?.copyWith(color: AppTheme.muted)),
      TextButton(onPressed: widget.onUndo, child: const Text('Ångra uppdelning')),
    ]);
  }
}

/// The box that "Markera som betald" opens: the payment date and how it was paid.
Future<({String date, PayMethod method, List<PaymentPart> split})?> askPayment(BuildContext context,
    {PayMethod initial = PayMethod.bank, CompanyForm? form, Money? total}) {
  var date = SwedishDates.iso(DateTime.now());
  var method = initial;
  var split = <PaymentPart>[];
  return showBlurDialog<({String date, PayMethod method, List<PaymentPart> split})>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text('Markera som betald'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final d = await showDatePicker(
                context: c,
                helpText: 'Betalningsdatum',
                initialDate: SwedishDates.parseIso(date) ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (d != null) setState(() => date = SwedishDates.iso(d));
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Betalningsdatum', suffixIcon: Icon(AppIcons.calendar)),
              child: Text(date),
            ),
          ),
          const SizedBox(height: 12),
          PayMethodChoice(
            value: method,
            form: form,
            onChanged: (m) => setState(() => method = m),
            total: total,
            split: split,
            onSplit: total == null ? null : (p) => setState(() => split = p),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Avbryt')),
          FilledButton(
            onPressed: () {
              if (split.length > 1 && !PaymentPart.valid(split, total!.abs())) {
                ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Delbeloppen måste vara över 0 och bli hela summan.')));
                return;
              }
              final sign = (total?.isNegative ?? false) ? -1 : 1;
              final parts = split.length > 1 ? [for (final p in split) PaymentPart(p.method, Money(p.amount.ore * sign))] : <PaymentPart>[];
              final main = parts.isEmpty
                  ? method
                  : (parts.toList()..sort((a, b) => b.amount.ore.abs().compareTo(a.amount.ore.abs()))).first.method;
              Navigator.pop(c, (date: date, method: main, split: parts));
            },
            child: const Text('Markera som betald'),
          ),
        ],
      ),
    ),
  );
}
