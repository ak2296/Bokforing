/// What an invoice was for. Used for the resultatrapport and, through the
/// BAS account, for the SIE export to the accountant.
class CostType {
  final String key;
  final String label;

  /// BAS account for the cost (excl. VAT).
  final int account;
  const CostType(this.key, this.label, this.account);

  static const goods = CostType('varuinkop', 'Varuinköp', 4010);
  static const rent = CostType('lokalhyra', 'Lokalhyra', 5010);
  static const energy = CostType('el', 'El, vatten och värme', 5020);
  static const supplies = CostType('forbrukning', 'Förbrukningsmaterial', 5460);
  static const inventory = CostType('inventarier', 'Inventarier och verktyg', 5410);
  static const repairs = CostType('reparation', 'Reparation och underhåll', 5500);
  static const cleaning = CostType('stadning', 'Städning och renhållning', 5060);
  static const security = CostType('larm', 'Säkerhet (larm, kameror, bevakning)', 5090);
  static const transport = CostType('transport', 'Frakt och transport', 5710);
  static const vehicle = CostType('fordon', 'Fordon och drivmedel', 5610);
  static const marketing = CostType('reklam', 'Reklam och marknadsföring', 5910);
  static const phone = CostType('telefon', 'Telefon och internet', 6210);
  static const insurance = CostType('forsakring', 'Försäkringar', 6310);
  static const software = CostType('programvara', 'Programvara och kassasystem', 5420);
  static const accounting = CostType('redovisning', 'Redovisning och konsulter', 6530);
  static const bankFees = CostType('bankavgifter', 'Bank- och kortavgifter', 6570);
  static const partnerFees = CostType('provision', 'Provision till onlinepartner', 6060);
  static const other = CostType('ovrigt', 'Övriga kostnader', 6990);

  /// Set by the app for a lönebesked: bruttolön and arbetsgivaravgift.
  static const salaries = CostType('loner', 'Löner', 7010);
  static const socialFees = CostType('sociala', 'Sociala avgifter', 7510);

  static const all = [
    goods, rent, energy, supplies, inventory, repairs, cleaning, security, transport, vehicle, marketing, phone, insurance,
    software, accounting, bankFees, partnerFees, salaries, socialFees, other,
  ];

  /// Null for an invoice saved without a cost type.
  static CostType? byKey(String key) {
    for (final c in all) {
      if (c.key == key) return c;
    }
    return null;
  }

  /// Label for reports; invoices without a type are shown apart.
  static String labelFor(String key) => byKey(key)?.label ?? 'Ej vald kostnadstyp';
}
