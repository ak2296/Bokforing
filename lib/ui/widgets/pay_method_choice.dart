import 'package:flutter/material.dart';

import '../../domain/dates.dart';
import '../../domain/models.dart';
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
  const PayMethodChoice({
    super.key,
    required this.value,
    required this.onChanged,
    this.confirmed = true,
    this.suggestion,
    this.form,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final unsure = !confirmed;
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
      ]),
    );
  }
}

/// The box that "Markera som betald" opens: the payment date and how it was paid.
Future<({String date, PayMethod method})?> askPayment(BuildContext context, {PayMethod initial = PayMethod.bank, CompanyForm? form}) {
  var date = SwedishDates.iso(DateTime.now());
  var method = initial;
  return showBlurDialog<({String date, PayMethod method})>(
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
          PayMethodChoice(value: method, form: form, onChanged: (m) => setState(() => method = m)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Avbryt')),
          FilledButton(onPressed: () => Navigator.pop(c, (date: date, method: method)), child: const Text('Markera som betald')),
        ],
      ),
    ),
  );
}
