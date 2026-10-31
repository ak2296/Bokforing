import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../domain/invoice_prefs.dart';

/// Lets the owner choose which printed fields the invoice reader may use.
class InvoiceFieldsPage extends StatefulWidget {
  const InvoiceFieldsPage({super.key});

  @override
  State<InvoiceFieldsPage> createState() => _InvoiceFieldsPageState();
}

class _InvoiceFieldsPageState extends State<InvoiceFieldsPage> {
  InvoicePrefs? _prefs;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefs == null) {
      AppScope.read(context).repo.invoicePrefs().then((p) {
        if (mounted) setState(() => _prefs = p);
      });
    }
  }

  Future<void> _save(InvoicePrefs p) async {
    setState(() => _prefs = p);
    await AppScope.read(context).repo.saveInvoicePrefs(p);
  }

  @override
  Widget build(BuildContext context) {
    final p = _prefs;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Fält på fakturor')),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Välj vilka uppgifter på fakturan appen ska använda. Ändringen gäller nya skanningar. '
                      '"Momspliktigt belopp" används aldrig som summa eller moms.'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: Text('Datum som registreras', style: t.titleSmall),
                ),
                RadioGroup<InvoiceDateChoice>(
                  groupValue: p.dateChoice,
                  onChanged: (v) => _save(InvoicePrefs(dateChoice: v!, totalLabels: p.totalLabels, vatLabels: p.vatLabels)),
                  child: Column(
                    children: [
                      for (final c in InvoiceDateChoice.values) RadioListTile<InvoiceDateChoice>(value: c, title: Text(c.label)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: Text('Summa: rader som får användas', style: t.titleSmall),
                ),
                for (final e in InvoicePrefs.totalLabelOptions.entries)
                  CheckboxListTile(
                    title: Text(e.value),
                    value: p.totalLabels.contains(e.key),
                    onChanged: (v) {
                      final s = {...p.totalLabels};
                      v == true ? s.add(e.key) : s.remove(e.key);
                      if (s.isEmpty) return;
                      _save(InvoicePrefs(dateChoice: p.dateChoice, totalLabels: s, vatLabels: p.vatLabels));
                    },
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: Text('Moms: rader som får användas', style: t.titleSmall),
                ),
                for (final e in InvoicePrefs.vatLabelOptions.entries)
                  CheckboxListTile(
                    title: Text(e.value),
                    value: p.vatLabels.contains(e.key),
                    onChanged: (v) {
                      final s = {...p.vatLabels};
                      v == true ? s.add(e.key) : s.remove(e.key);
                      _save(InvoicePrefs(dateChoice: p.dateChoice, totalLabels: p.totalLabels, vatLabels: s));
                    },
                  ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Du kan alltid välja ett annat datum eller belopp på granskningsskärmen.'),
                ),
              ],
            ),
    );
  }
}
