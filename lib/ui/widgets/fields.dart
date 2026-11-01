import 'package:flutter/material.dart';

import '../app_icons.dart';

import '../../domain/dates.dart';
import '../../domain/money.dart';
import '../../domain/text_patterns.dart';
import '../theme.dart';

/// ✓ for confident values, ⚠ for values the user should check.
class ConfidenceBadge extends StatelessWidget {
  final Confidence? confidence;
  const ConfidenceBadge(this.confidence, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = confidence;
    if (c == null) return const SizedBox.shrink();
    final high = c == Confidence.high;
    return Tooltip(
      message: c.label,
      child: Icon(high ? AppIcons.checkCircle : AppIcons.warning,
          color: high ? AppTheme.ok : AppTheme.warning, semanticLabel: c.label),
    );
  }
}

InputDecoration _decoration(BuildContext context, String label, Confidence? c, {String? hint, String? suffix}) {
  final low = c != null && c != Confidence.high;
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixText: suffix,
    filled: low,
    fillColor: low ? AppTheme.warning.withValues(alpha: 0.08) : null,
    helperText: low ? (c == Confidence.low ? 'Osäker – kontrollera' : 'Kontrollera') : null,
    prefixIcon: c == null ? null : Padding(padding: const EdgeInsets.all(12), child: ConfidenceBadge(c)),
  );
}

class MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final Confidence? confidence;
  final bool enabled;
  final bool required;
  final ValueChanged<String>? onChanged;

  const MoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.confidence,
    this.enabled = true,
    this.required = true,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        enabled: enabled,
        style: moneyStyle,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: _decoration(context, label, confidence, hint: 't.ex. 1250,50', suffix: 'kr'),
        onChanged: onChanged,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (v) {
          if ((v ?? '').trim().isEmpty) return required ? 'Fyll i beloppet' : null;
          return Money.parse(v!) == null ? 'Ange ett belopp, t.ex. 1250,50' : null;
        },
      );
}

class DateField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final Confidence? confidence;
  final bool enabled;
  final bool required;
  final ValueChanged<String>? onChanged;

  const DateField({
    super.key,
    required this.controller,
    required this.label,
    this.confidence,
    this.enabled = true,
    this.required = true,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.datetime,
        decoration: _decoration(context, label, confidence, hint: 'ÅÅÅÅ-MM-DD').copyWith(
          suffixIcon: IconButton(
            tooltip: 'Välj datum',
            icon: const Icon(AppIcons.calendar),
            onPressed: !enabled
                ? null
                : () async {
                    final initial = SwedishDates.parseIso(controller.text) ?? DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: initial,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      controller.text = SwedishDates.iso(picked);
                      onChanged?.call(controller.text);
                    }
                  },
          ),
        ),
        onChanged: onChanged,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (v) {
          if ((v ?? '').trim().isEmpty) return required ? 'Fyll i datum' : null;
          return SwedishDates.isValidIso(v!) ? null : 'Skriv datum som ÅÅÅÅ-MM-DD';
        },
      );
}

class PlainField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final Confidence? confidence;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;

  const PlainField({
    super.key,
    required this.controller,
    required this.label,
    this.confidence,
    this.enabled = true,
    this.onChanged,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        decoration: _decoration(context, label, confidence),
        onChanged: onChanged,
      );
}
