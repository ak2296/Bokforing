/// Which date on an invoice becomes the bookkeeping date.
enum InvoiceDateChoice { invoiceDate, dueDate, paymentDate }

extension InvoiceDateChoiceText on InvoiceDateChoice {
  String get label => switch (this) {
        InvoiceDateChoice.invoiceDate => 'Fakturadatum / Datum',
        InvoiceDateChoice.dueDate => 'Förfallodatum',
        InvoiceDateChoice.paymentDate => 'Betalningsdatum',
      };
}

/// The owner's choice of which printed fields the invoice reader may use.
/// Labels that are switched off are never used for the total or VAT.
class InvoicePrefs {
  final InvoiceDateChoice dateChoice;
  final Set<String> totalLabels;
  final Set<String> vatLabels;

  const InvoicePrefs({
    this.dateChoice = InvoiceDateChoice.invoiceDate,
    this.totalLabels = const {'att betala', 'summa', 'totalt', 'betalt belopp', 'brutto', 'fakturabelopp'},
    this.vatLabels = const {'moms', 'momsbelopp', 'varav moms', 'total moms'},
  });

  /// Groups shown in Inställningar, key -> Swedish label.
  static const totalLabelOptions = {
    'att betala': 'Att betala',
    'summa': 'Summa',
    'totalt': 'Totalt / Total',
    'betalt belopp': 'Betalt belopp',
    'brutto': 'Brutto',
    'fakturabelopp': 'Fakturabelopp',
  };

  static const vatLabelOptions = {
    'moms': 'Moms (t.ex. "Moms 25 %")',
    'momsbelopp': 'Momsbelopp',
    'varav moms': 'Varav moms',
    'total moms': 'Total moms / Summa moms',
  };

  static const dateKey = 'invoice_date_choice';
  static const totalKey = 'invoice_total_labels';
  static const vatKey = 'invoice_vat_labels';

  static InvoicePrefs decode({String? date, String? totals, String? vats}) {
    const d = InvoicePrefs();
    Set<String>? split(String? s) => s == null ? null : s.split('|').where((x) => x.isNotEmpty).toSet();
    return InvoicePrefs(
      dateChoice: InvoiceDateChoice.values.firstWhere((c) => c.name == date, orElse: () => d.dateChoice),
      totalLabels: split(totals) ?? d.totalLabels,
      vatLabels: split(vats) ?? d.vatLabels,
    );
  }

  String get encodedTotals => totalLabels.join('|');
  String get encodedVats => vatLabels.join('|');
}
