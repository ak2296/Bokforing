import 'dart:convert';
import 'dart:typed_data';

import '../domain/ledger.dart';
import '../domain/money.dart';
import '../domain/report_period.dart';

/// One box the owner can fill in by hand: the ruta number, what it is called on
/// Skatteverket's form, and the XML element it goes into.
class VatField {
  final int box;
  final String label;
  final String element;
  const VatField(this.box, this.label, this.element);
}

/// A group of boxes on the page "Egna uppgifter".
class VatGroup {
  final String title;
  final List<VatField> fields;
  const VatGroup(this.title, this.fields);
}

/// The boxes Quee cannot work out from the registered documents. The owner types
/// them when they have the figures. Box 48 here is *extra* input VAT, added to
/// what Quee found.
const vatManualGroups = <VatGroup>[
  VatGroup('EU-handel och export (utan moms)', [
    VatField(35, 'Varor till annat EU-land', 'ForsVaruAnnatEg'),
    VatField(36, 'Export av varor utanför EU', 'ForsVaruUtomEg'),
    VatField(39, 'Tjänster till företag i annat EU-land', 'ForsTjSkskAnnatEg'),
    VatField(40, 'Övriga tjänster som inte säljs i Sverige', 'ForsTjOvrUtomEg'),
    VatField(41, 'Försäljning där köparen betalar momsen i Sverige', 'ForsKopareSkskSverige'),
    VatField(37, 'Mellanmans inköp vid trepartshandel', 'InkopVaruMellan3p'),
    VatField(38, 'Mellanmans försäljning vid trepartshandel', 'ForsVaruMellan3p'),
    VatField(42, 'Övrig försäljning utan moms (läggs till det Quee hittat)', 'ForsOvrigt'),
  ]),
  VatGroup('Köp med omvänd skattskyldighet', [
    VatField(20, 'Varor från annat EU-land (underlag)', 'InkopVaruAnnatEg'),
    VatField(21, 'Tjänster från annat EU-land (underlag)', 'InkopTjanstAnnatEg'),
    VatField(22, 'Tjänster från land utanför EU (underlag)', 'InkopTjanstUtomEg'),
    VatField(23, 'Varor i Sverige, köparen betalar moms (underlag)', 'InkopVaruSverige'),
    VatField(24, 'Tjänster i Sverige, köparen betalar moms (underlag)', 'InkopTjanstSverige'),
    VatField(30, 'Utgående moms 25 % på ruta 20-24', 'MomsInkopUtgHog'),
    VatField(31, 'Utgående moms 12 % på ruta 20-24', 'MomsInkopUtgMedel'),
    VatField(32, 'Utgående moms 6 % på ruta 20-24', 'MomsInkopUtgLag'),
    VatField(48, 'Extra ingående moms du får dra av (till ruta 48)', 'MomsIngAvdr'),
  ]),
  VatGroup('Import, uttag och övrigt', [
    VatField(50, 'Import: beskattningsunderlag', 'MomsUlagImport'),
    VatField(60, 'Utgående moms på import 25 %', 'MomsImportUtgHog'),
    VatField(61, 'Utgående moms på import 12 %', 'MomsImportUtgMedel'),
    VatField(62, 'Utgående moms på import 6 %', 'MomsImportUtgLag'),
    VatField(6, 'Uttag av varor eller tjänster (underlag)', 'UttagMoms'),
    VatField(7, 'Underlag vid vinstmarginalbeskattning', 'UlagMargbesk'),
    VatField(8, 'Hyresintäkter vid frivillig skattskyldighet', 'HyrinkomstFriv'),
  ]),
];

/// The boxes in the order the file lists them (the form's own order).
const _xmlOrder = <(int, String)>[
  (5, 'ForsMomsEjAnnan'),
  (6, 'UttagMoms'),
  (7, 'UlagMargbesk'),
  (8, 'HyrinkomstFriv'),
  (10, 'MomsUtgHog'),
  (11, 'MomsUtgMedel'),
  (12, 'MomsUtgLag'),
  (20, 'InkopVaruAnnatEg'),
  (21, 'InkopTjanstAnnatEg'),
  (22, 'InkopTjanstUtomEg'),
  (23, 'InkopVaruSverige'),
  (24, 'InkopTjanstSverige'),
  (30, 'MomsInkopUtgHog'),
  (31, 'MomsInkopUtgMedel'),
  (32, 'MomsInkopUtgLag'),
  (35, 'ForsVaruAnnatEg'),
  (36, 'ForsVaruUtomEg'),
  (37, 'InkopVaruMellan3p'),
  (38, 'ForsVaruMellan3p'),
  (39, 'ForsTjSkskAnnatEg'),
  (40, 'ForsTjOvrUtomEg'),
  (41, 'ForsKopareSkskSverige'),
  (42, 'ForsOvrigt'),
  (50, 'MomsUlagImport'),
  (60, 'MomsImportUtgHog'),
  (61, 'MomsImportUtgMedel'),
  (62, 'MomsImportUtgLag'),
  (48, 'MomsIngAvdr'),
];

const _boxTexts = <int, String>{
  5: 'Momspliktig försäljning (utan moms)',
  10: 'Utgående moms 25 %',
  11: 'Utgående moms 12 %',
  12: 'Utgående moms 6 %',
  42: 'Övrig försäljning utan moms',
  48: 'Ingående moms att dra av',
};

/// The figures of one momsdeklaration in whole kronor, and the XML file
/// ("eSKDUpload" version 6.0) that Skatteverket's e-service "Lämna momsdeklaration"
/// takes under "Deklarera via fil". The owner uploads it there and signs with
/// e-legitimation; the app sends nothing.
///
/// Built from the SIE accounts (3001-3003 sales, 2611-2631 output VAT, 2641 input
/// VAT) plus the figures the owner typed by hand ([manual]). Quee does not check
/// the typed figures.
class VatReturn {
  /// `xxxxxx-xxxx`, as Skatteverket wants it.
  final String orgNr;

  /// `YYYYMM`: the month, or the last month of the quarter or year.
  final String period;

  /// Ruta number to whole kronor: what Quee found plus what the owner typed.
  final Map<int, int> values;

  /// The boxes that carry something the owner typed.
  final Set<int> manualBoxes;
  const VatReturn({required this.orgNr, required this.period, required this.values, this.manualBoxes = const {}});

  int box(int n) => values[n] ?? 0;
  int get base => box(5);
  int get outHigh => box(10);
  int get outMid => box(11);
  int get outLow => box(12);
  int get other => box(42);
  int get input => box(48);

  /// Ruta 49: output VAT (10, 11, 12, 30, 31, 32, 60, 61, 62) minus input VAT (48).
  /// Negative means VAT to get back.
  int get toPay => [10, 11, 12, 30, 31, 32, 60, 61, 62].fold(0, (a, n) => a + box(n)) - input;

  /// The period kinds a VAT return exists for.
  static bool supports(PeriodKind k) => k == PeriodKind.month || k == PeriodKind.quarter || k == PeriodKind.year;

  /// `xxxxxx-xxxx` from what the owner typed (with or without hyphen, 10 or 12
  /// digits), or null when it is not an organisation or personal number.
  static String? normaliseOrgNr(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12) digits = digits.substring(2);
    if (digits.length != 10) return null;
    return '${digits.substring(0, 6)}-${digits.substring(6)}';
  }

  /// The figures of [period] from the ledger, plus [manual] (ruta to whole kronor).
  /// Each ledger figure is rounded to whole kronor first, so the file adds up the
  /// way Skatteverket checks it.
  factory VatReturn.fromLedger(Ledger l, ReportPeriod period, String orgNr, {Map<int, int> manual = const {}}) {
    int kr(Money m) => m.roundedToKr().ore ~/ 100;
    int sales(int account) => kr(-l.balanceOf(account));
    final end = period.toDate;
    final values = <int, int>{
      5: sales(3001) + sales(3002) + sales(3003),
      10: sales(2611),
      11: sales(2621),
      12: sales(2631),
      42: sales(3004) + sales(3000),
      48: kr(l.balanceOf(2641)),
    };
    final typed = <int>{};
    for (final e in manual.entries) {
      if (e.value == 0) continue;
      values[e.key] = (values[e.key] ?? 0) + e.value;
      typed.add(e.key);
    }
    return VatReturn(
      orgNr: orgNr,
      period: '${end.year}${end.month.toString().padLeft(2, '0')}',
      values: values,
      manualBoxes: typed,
    );
  }

  /// The XML text. Elements come in the order the form lists them; a box that is
  /// zero is left out, except ruta 49 which is always there. No spaces or tabs
  /// inside the lines: the e-service rejects them.
  String toXml() => [
        '<?xml version="1.0" encoding="ISO-8859-1"?>',
        '<eSKDUpload Version="6.0">',
        '<OrgNr>$orgNr</OrgNr>',
        '<Moms>',
        '<Period>$period</Period>',
        for (final (n, element) in _xmlOrder)
          if (box(n) != 0) '<$element>${box(n)}</$element>',
        '<MomsBetala>$toPay</MomsBetala>',
        '</Moms>',
        '</eSKDUpload>',
      ].join('\r\n');

  /// The file as Skatteverket reads it: ISO-8859-1.
  Uint8List toBytes() => Uint8List.fromList(latin1.encode(toXml()));

  String get fileName => 'momsdeklaration_$period.xml';

  /// The boxes for the screen: (ruta, text, amount in kronor, typed by the owner),
  /// in ruta order, zero boxes left out.
  List<(String, String, int, bool)> get boxes {
    final labels = {for (final g in vatManualGroups) for (final f in g.fields) f.box: f.label, ..._boxTexts};
    final order = [for (final (n, _) in _xmlOrder) n]..sort();
    return [
      for (final n in order)
        if (box(n) != 0)
          (n.toString().padLeft(2, '0'), _boxTexts[n] ?? labels[n] ?? '', box(n), manualBoxes.contains(n)),
      ('49', toPay >= 0 ? 'Moms att betala' : 'Moms att få tillbaka', toPay, false),
    ];
  }
}
