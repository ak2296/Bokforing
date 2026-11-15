import 'dart:convert';

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
  static const membership = CostType('medlemskap', 'Avgifter och medlemskap', 6980);
  static const media = CostType('musik_tv', 'Musik och TV (licenser, abonnemang)', 6990);
  static const other = CostType('ovrigt', 'Övriga kostnader', 6990);

  /// Set by the app for a lönebesked: bruttolön and arbetsgivaravgift.
  static const salaries = CostType('loner', 'Löner', 7010);
  static const socialFees = CostType('sociala', 'Sociala avgifter', 7510);

  static const all = [
    goods, rent, energy, supplies, inventory, repairs, cleaning, security, transport, vehicle, marketing, phone, insurance,
    software, accounting, bankFees, partnerFees, membership, media, salaries, socialFees, other,
  ];

  /// Types the owner added for costs that no standard type covers. They are
  /// kept in the settings (see [encodeCustom]) and loaded when the app starts.
  static List<CostType> custom = const [];

  /// Built-in and own types, for lookups and report order.
  static List<CostType> get every => [...all, ...custom];

  /// For the choice lists: the built-in types, the owner's own, and Övriga last.
  static List<CostType> get selectable => [for (final c in all) if (c != other) c, ...custom, other];

  static String encodeCustom(List<CostType> types) =>
      jsonEncode([for (final c in types) {'key': c.key, 'label': c.label, 'account': c.account}]);

  static List<CostType> decodeCustom(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      return [
        for (final m in (jsonDecode(json) as List).cast<Map<String, Object?>>())
          CostType(m['key'] as String, m['label'] as String, (m['account'] as num?)?.toInt() ?? 6990),
      ];
    } on Object {
      return const [];
    }
  }

  /// A new own type from a name, with a key that is not taken.
  static CostType newCustom(String label, {int account = 6990}) {
    final base = 'egen_${label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9åäö]+'), '_')}';
    var key = base, n = 2;
    while (byKey(key) != null) {
      key = '${base}_$n';
      n++;
    }
    return CostType(key, label.trim(), account);
  }

  /// Null for an invoice saved without a cost type.
  static CostType? byKey(String key) {
    for (final c in every) {
      if (c.key == key) return c;
    }
    return null;
  }

  /// Label for reports; invoices without a type are shown apart.
  static String labelFor(String key) => byKey(key)?.label ?? 'Ej vald kostnadstyp';
}
