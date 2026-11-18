import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/pay_method.dart';
import 'package:bokforing/domain/payment_detector.dart';
import 'package:bokforing/domain/text_merge.dart';
import 'package:bokforing/domain/text_patterns.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:bokforing/domain/z_report_parser.dart';
import 'package:flutter_test/flutter_test.dart';

// Synthetic texts with the structure of real phone readings; the figures
// are made up.
const _cats = [
  Category(id: 1, name: 'Mat', vat: VatRate.twelve),
  Category(id: 2, name: 'Drycka', vat: VatRate.twelve),
  Category(id: 3, name: 'Tobak', vat: VatRate.twentyFive),
  Category(id: 4, name: 'Öl', vat: VatRate.twentyFive),
  Category(id: 5, name: 'Sprit', vat: VatRate.twentyFive),
  Category(id: 6, name: 'Avhämtning', vat: VatRate.six),
];
const _aliases = {'Mat avhämtning': 6, 'Drycka avhämtning': 6};

ZReportDraft _read(String text) =>
    ZReportParser(_cats, aliases: _aliases, today: DateTime(2026, 11, 18)).parse(OcrResult.fromPlainText(text));

List<(String, Money)> _lines(ZReportDraft d) => [for (final l in d.lines) (l.label, l.amount)];

/// A4 print-out where every amount was read on the line above its name.
const _amountAbove = '''
Z-Rapport: Alla kassor   :00- 2026-11-10
Från:   2026-11-10 10:05 O   Exempel restaurang
Till:   2026-11-10 21:40 Ti   Exempelgatan 1
Underlag: Z1-55
GENERELLT
Periodens försäljining   4 360,00 kr
Periodens försäljning exkl moms   3 900,10 kr
KASSALADA OCH VÄXELKASSA
Antal lådöppningar
Kontanter:
400,00 kr
Ingående växelkassa
150,00 kr
Betalningar
550,00 kr
Utgående växelkassa
BETALMETODER
4 210,00 kr
Kort
150.00 kr
Kontanter
PERIODENS FÖRSÄLJNING EXKL RET
0,00 kr
Tjänster
4 360,00 kr
Varor
FÖRSALJNING PER VARUGRUPP EXKL
60.00 kr
Drycka
310.00 kr
Drycka avhämtning
820,00 kr
Mat
1 040,00 kr
Mat avhämtning
1 230,00 kr
Tobak
900,00 kr
öl
https:/exempel360,com/#/reports/z-report
1/2''';

void main() {
  test('space thousands and dot decimals are read as amounts', () {
    for (final (text, kr) in [('5 105,00 kr', 5105), ('135.00 kr', 135), ('1 119,00', 1119), ('2 100,00 kr', 2100)]) {
      expect(TextPatterns.amounts(text).single.value, Money.kr(kr), reason: text);
    }
  });

  test('amount on the line above its name: categories and card/cash are paired with the name below', () {
    final d = _read(_amountAbove);
    expect(_lines(d), [
      ('Drycka', Money.kr(60)),
      ('Drycka avhämtning', Money.kr(310)),
      ('Mat', Money.kr(820)),
      ('Mat avhämtning', Money.kr(1040)),
      ('Tobak', Money.kr(1230)),
      ('öl', Money.kr(900)),
    ]);
    expect(d.total.value, Money.kr(4360));
    expect(d.cash.card.value, Money.kr(4210));
    expect(d.cash.cash.value, Money.kr(150));
    expect(d.cash.card.confidence, Confidence.high);
    expect(d.notes.any((n) => n.contains('inte på samma rad')), isTrue);
    expect(d.zNumber.value, 'Z1-55');
    expect(d.date.value, '2026-11-10');
  });

  test('some names on the same line as their amount, others below it, last name lost', () {
    final d = _read('''
Z-Rapport
Från:   2026-11-11 11:00
Periodens försäljning   3 105,00 kr
BETALMETODER
Kort   x 20   2 800,00 kr
Kontanter   x2   305,00 kr
FÖRSALJNING PER VARUGRUPP EXKL RETURER
40,00 kr
Drycka
Drycka avhämtning   115,00 kr
1 000,00 kr
Mat
Mat avhämtning   700,00 kr
650,00 kr
Tobak
600,00 kr
sprit
1/2''');
    expect(_lines(d), [
      ('Drycka', Money.kr(40)),
      ('Drycka avhämtning', Money.kr(115)),
      ('Mat', Money.kr(1000)),
      ('Mat avhämtning', Money.kr(700)),
      ('Tobak', Money.kr(650)),
      ('sprit', Money.kr(600)),
    ]);
    expect(d.cash.card.value, Money.kr(2800));
    expect(d.cash.cash.value, Money.kr(305));
  });

  test('a name with its amount on the next line still pairs the old way', () {
    final d = _read('Z-rapport\nFörsäljning per varugrupp\nMat\n1 912,00\nTobak\n89,00\nTotal försäljning\n2 001,00');
    expect(_lines(d), [('Mat', Money.kr(1912)), ('Tobak', Money.kr(89))]);
  });

  test('badly read thermal Z-report: fuzzy heading, whole amounts, receipts total, no all-time sums', () {
    final d = _read('''
Exempel pizzeria
Z-RAPPORT
2026-11 -12 11:10:
2026-11-12 21:58:r5
PuricuEDS forSaljni:19
Kort 30)   5 410,00
huntnlu (2)   205,00
For sal jing pe varuiyr upp txH1 eturer
Drycka   40
XDycka avhantning   95,00
1 020.):
WMat avhatuILng   1 210.
spril   350.00
Tubak   500.00
2 400,00
För:säljniig per momsgrupp exki retur er
6.00 %   1 283.o
Kyilloi
Füradljningskvillon i32)   5 615,00
Grond total
Forsaljnng (9 990)   1 818 215,20
Boh Lörngsunderlag
150001 Försäljniig Drycha   -35,72
Rapport 21-498''');
    expect(d.sectionFound, isTrue);
    expect(d.total.value, Money.kr(5615));
    expect(Money.sum(d.lines.map((l) => l.amount)), Money.kr(5615));
    expect(d.lines.first.categoryId, 2);
    expect(d.zNumber.value, isNot('2026'));
    expect(d.cash.card.value, Money.kr(5410));
    expect(d.cash.cash.value, Money.kr(205));
    expect(d.date.value, '2026-11-12');
  });

  test('without a sales section, all-time sums and account rows are not sales', () {
    final d = _read('Z-rapport\nMat   500,00\nTobak   300,00\nGrand total\nMat   812 000,00\nBokföringsunderlag\n150002 Försäljning Mat   -978,56');
    expect(_lines(d), [('Mat', Money.kr(500)), ('Tobak', Money.kr(300))]);
  });

  group('Joining photos of a long receipt', () {
    List<String> merge(List<String> parts) =>
        TextMerge.merge([for (final p in parts) OcrResult.fromPlainText(p)]).rows().map((r) => r.text).toList();

    test('the overlap read differently in each photo appears once', () {
      final rows = merge([
        'Exempel pizzeria\nZ-RAPPORT\nPeriodens försäljning   3 615,00\nKontanter:\nIngående växelkassa   500,00\n'
            'Betalningar   205.00\nKort 30)   3 410,00\nD\'ycha   40 oo\n1 020. k0:',
        'Kontantu:\nIngaende vanclkassa   500,4\nBetalnigui   205,00\nKe t (30)   3 410.0G\n'
            'Drycka   40\n1 020.):\nTobak   500,00\nGrand total',
      ]);
      expect(rows.where((r) => r.contains('3 410')).length, 1);
      expect(rows.where((r) => r.contains('1 020')).length, 1);
      expect(rows.first, 'Exempel pizzeria');
      expect(rows.last, 'Grand total');
      expect(rows, contains('Tobak   500,00'));
    });

    test('two pages with the same letterhead are not cut', () {
      const head = 'Exempel AB\nExempelgatan 1\n212 24 Malmö\nOrg.nr 556000-0000';
      final rows = merge(['$head\nVara A   100,00\nVara B   200,00\nVara C   300,00', '$head\nVara D   400,00\nSumma   1 000,00']);
      expect(rows.length, 4 + 3 + 4 + 2);
    });
  });

  test('payment terms "Kontant" on its own row, amount above: Kontant is suggested', () {
    final p = const PaymentDetector().detect(['Kvitto', 'Exempel Grossist AB', 'Pant 3kr', '1 166.00', 'Kontant', 'Netto   1 068.68', 'Att betala SEK   1 166.00']);
    expect(p.method, PayMethod.cash);
    expect(p.methodReason, contains('Kontant'));
  });
}
