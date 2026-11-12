import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    // Säker green check, Kontrollera yellow triangle, Osäker pumpkin question mark.
    final (icon, color) = switch (c) {
      Confidence.high => (AppIcons.checkCircle, AppTheme.ok),
      _ => (AppIcons.warning, AppTheme.unsure),
    };
    return Tooltip(message: c.label, child: Icon(icon, color: color, semanticLabel: c.label));
  }
}

InputDecoration _decoration(BuildContext context, String label, Confidence? c, {String? hint, String? suffix}) {
  final low = c != null && c != Confidence.high;
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixText: suffix,
    filled: low,
    fillColor: !low ? null : AppTheme.unsureTint,
    helperText: low ? 'Kontrollera' : null,
    helperStyle: !low ? null : TextStyle(color: AppTheme.unsure),
    prefixIcon: c == null ? null : Padding(padding: const EdgeInsets.all(12), child: ConfidenceBadge(c)),
  );
}

class MoneyField extends StatefulWidget {
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
  State<MoneyField> createState() => _MoneyFieldState();
}

/// Shows 1 250,50 when the field is not being edited, and 1250,50 while it is.
class _MoneyFieldState extends State<MoneyField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    widget.controller.addListener(_tidy);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tidy());
  }

  @override
  void didUpdateWidget(MoneyField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_tidy);
      widget.controller.addListener(_tidy);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_tidy);
    _focus.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focus.hasFocus) return _tidy();
    final text = widget.controller.text;
    final plain = text.replaceAll(RegExp(r'\s'), '');
    if (plain != text) {
      widget.controller.value = TextEditingValue(text: plain, selection: TextSelection.collapsed(offset: plain.length));
    }
  }

  void _tidy() {
    if (!mounted || _focus.hasFocus) return;
    final m = Money.parse(widget.controller.text);
    if (m == null) return;
    final shown = m.format(unit: false);
    if (shown != widget.controller.text) widget.controller.text = shown;
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        focusNode: _focus,
        enabled: widget.enabled,
        style: moneyStyle,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: _decoration(context, widget.label, widget.confidence, hint: 't.ex. 1250,50', suffix: 'kr'),
        onChanged: widget.onChanged,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (v) {
          if ((v ?? '').trim().isEmpty) return widget.required ? 'Fyll i beloppet' : null;
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
        keyboardType: TextInputType.number,
        inputFormatters: [_IsoDateFormatter()],
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

/// Types a date as digits; the dashes are put in: 20261028 becomes 2026-10-28.
class _IsoDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final d = digits.length > 8 ? digits.substring(0, 8) : digits;
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 4 || i == 6) b.write('-');
      b.write(d[i]);
    }
    final text = b.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
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
