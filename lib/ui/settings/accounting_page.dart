import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../data/accounting_settings.dart';
import '../../domain/report_period.dart';
import '../theme.dart';

/// Inställningar → Företag → Redovisning: how often underlag goes to the
/// accountant, and who the accountant is (for the e-mail and the SMS).
class AccountingPage extends StatefulWidget {
  const AccountingPage({super.key});

  @override
  State<AccountingPage> createState() => _AccountingPageState();
}

class _AccountingPageState extends State<AccountingPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _own = TextEditingController();
  PeriodKind _kind = PeriodKind.month;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      loadAccounting(AppScope.read(context).repo).then((s) {
        if (!mounted) return;
        setState(() {
          _kind = s.kind;
          _name.text = s.accountantName;
          _email.text = s.accountantEmail;
          _phone.text = s.accountantPhone;
          _own.text = s.ownerEmail;
        });
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _own]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() => saveAccounting(
        AppScope.read(context).repo,
        AccountingSettings(
          kind: _kind,
          accountantName: _name.text,
          accountantEmail: _email.text,
          accountantPhone: _phone.text,
          ownerEmail: _own.text,
        ),
      );

  Widget _field(TextEditingController c, String label, {TextInputType? type, String? hint}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextField(
          controller: c,
          keyboardType: type,
          autocorrect: false,
          textCapitalization: type == null ? TextCapitalization.words : TextCapitalization.none,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onChanged: (_) => _save(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Redovisning')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('HUR OFTA LÄMNAR DU UNDERLAG?', style: t.labelMedium?.copyWith(color: AppTheme.muted, letterSpacing: 0.4)),
                const SizedBox(height: 8),
                SegmentedButton<PeriodKind>(
                  expandedInsets: EdgeInsets.zero,
                  showSelectedIcon: false,
                  segments: [for (final k in PeriodKind.values) ButtonSegment(value: k, label: Text(k.label))],
                  selected: {_kind},
                  onSelectionChanged: (s) {
                    setState(() => _kind = s.first);
                    _save();
                  },
                ),
                const SizedBox(height: 8),
                Text(
                    'Det här blir förvalet i Resultat och Redovisarpaket. Du kan alltid byta period där. Moms redovisas per månad, kvartal eller år, inte per halvår. Skatteverket bestämmer vilken period just ditt företag har: kolla ditt momsregistreringsbevis.',
                    style: t.bodySmall),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('DIN REDOVISARE', style: t.labelMedium?.copyWith(color: AppTheme.muted, letterSpacing: 0.4)),
                _field(_name, 'Namn'),
                _field(_email, 'E-post', type: TextInputType.emailAddress, hint: 'namn@byra.se'),
                _field(_phone, 'Mobilnummer (för sms)', type: TextInputType.phone, hint: '070-123 45 67'),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('DU', style: t.labelMedium?.copyWith(color: AppTheme.muted, letterSpacing: 0.4)),
                _field(_own, 'Din e-post (för svar och signatur)', type: TextInputType.emailAddress),
                const SizedBox(height: 8),
                Text(
                    'Uppgifterna ligger bara i din telefon. Mejlet skickas från den e-postapp och det konto du själv väljer, och du trycker själv på skicka.',
                    style: t.bodySmall),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
