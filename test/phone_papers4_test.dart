import 'package:bokforing/domain/invoice_parser.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/payment_detector.dart';
import 'package:bokforing/domain/text_patterns.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:bokforing/domain/z_report_parser.dart';
import 'package:bokforing/imaging/preprocess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _cats = [
  Category(id: 1, name: 'Mat', vat: VatRate.twelve),
  Category(id: 2, name: 'Konfektyr', vat: VatRate.twelve),
  Category(id: 3, name: 'Tobak', vat: VatRate.twentyFive),
  Category(id: 4, name: 'Öl', vat: VatRate.twentyFive),
  Category(id: 5, name: 'Sprit', vat: VatRate.twentyFive),
  Category(id: 6, name: 'Vin', vat: VatRate.twentyFive),
  Category(id: 7, name: 'Cider', vat: VatRate.twentyFive),
  Category(id: 8, name: 'Avhämtning', vat: VatRate.six),
];
const _rules = {'drycka': 2, 'drycka avhämtning': 8, 'mat avhämtning': 8};

ZReportDraft _z(String text) => const ZReportParser(_cats, aliases: _rules).parse(OcrResult.fromPlainText(text));

/// The owner's real Z-reports, as the phone read them. "Öl" was not read.
const _nov2 = '''
Z-Rapport (2026-11-02 00:00 - 2026-11-02 23:59)
2026-11-04 20:32
Z-Rapport: Alla kassor (1 st)   2026-11-02 00:00 - 2026-11-02 23:59
Från:   2026-11-02 11:36 Org.nr: 121212-1212 Företag: Ankan restaurang & pizzeria
Till:   2026-11-02 22:21 Tid: 2026-11-04 20:31 Adress:   Provvägen 12 A 123 45 Malmö
Underlag: Z1-183
GENERELLT
Periodens försäljning   6 586,00 kr
Periodens försäljning exkl moms   5 530,59 kr
Öresutjämning   0.00 kr
Förskottsbetalningar   0,00 kr
Öppna notor   2579,00 kr
Dricks   0,00 kr
KASSALADA OCH VÄXELKASSA
Antal lädöppningar   x0
Kontanter:
Ingående växelkassa   500,00 kr
Betalningar   1 822,00 kr
Given växel   -478,00 kr
Utgående växelkassa   1 844.00 kr
BETALMETODER
Kort   53   5 242,00 kr
Kontanter   x 14   1344,00 kr
PERIODENS FÖRSÄLJNING EXKL RETURER
Tjänster   x 0   0,00 kr
Varor   x 108   6 586,00 kr
Rabatter   x0   0.00 kr
Skulder   x 0   0,00 kr
FÖRSÄLJNING PER VARUGRUPP EXKL RETURER
Cider
59,00 kr
Drycka   80.00 kr
Drycka avhämtning   414,00 kr
Mat
661,00 kr
Mat avhämtning   932,00 kr
Tobak   786,00 kr
3 654,00 kr
https://onslip360.com/t/reports/z-report
1/2''';

const _nov3 = '''
Z-Rapport (2026-11-03 00:00- 2026-11-03 23:59)
11-04 17.38
Z-Rapport: Alla kassor (1 st)   2026-11-03 00:00 - 2026-11-03 23:59
Fran:   2026-11-03 11:23 Org.nr: 121212-1212   Företag: Ankan restaurang & pizzeria
Till:   2026-11-03 22:29 Tid:   2026-11-04 17:37 Adress: Provvägen 12 A 123 45 Malmă
Underlag: Z1-184
GENERELLT
Periodens försäljning   9 261,00 kr
Perioderns försåljning exkl moms   7 935,91 kr
Öresutjämning   0,00 kr
BETALMETODER
Kort
x 78   8444,00 kr
Kontanter
x8   817,00 kr
PERIODENS FÖRSÄLJNING EXKL RETURER
Varor
x 151   9 261,00 kr
FORSALJNING PER VARUGRUPP EXKL RETURER
Drycka
260,00 kr
Drycka avhâmtning
149,00 kr
Mat
2 203,00 kr
Mat avhämtning
1932,00 kr
Tobak
638,00 kr
sprit
363,00 kr
3716,00 kr
Veportsrepont   1/2''';

/// One amount per row at the right, one name per row at the left, so the app
/// can try moving the amount column.
OcrResult _columns(List<(String, String?)> rows) {
  final lines = <OcrLine>[];
  for (var i = 0; i < rows.length; i++) {
    final top = i * 30.0;
    lines.add(OcrLine(rows[i].$1, OcrBox(50, top, 350, top + 20)));
    final amount = rows[i].$2;
    if (amount != null) lines.add(OcrLine(amount, OcrBox(800, top, 920, top + 20)));
  }
  return OcrResult(text: '', blocks: [for (final l in lines) OcrBlock(l.text, l.box, [l])]);
}

void main() {
  group('Z-report 2 November', () {
    final d = _z(_nov2);

    test('names keep their own amounts', () {
      Money amount(String label) => d.lines.firstWhere((l) => l.label == label).amount;
      expect(amount('Cider'), Money.kr(59));
      expect(amount('Drycka'), Money.kr(80));
      expect(amount('Drycka avhämtning'), Money.kr(414));
      expect(amount('Mat'), Money.kr(661));
      expect(amount('Mat avhämtning'), Money.kr(932));
      expect(amount('Tobak'), Money.kr(786));
      expect(d.total.value, Money.kr(6586));
    });

    test('the amount with no readable name is kept and Öl is suggested', () {
      final l = d.lines.firstWhere((l) => l.label == ZLine.unnamed);
      expect(l.amount, Money.kr(3654));
      expect(l.categoryId, isNull);
      expect(l.suggestedCategoryId, 4);
      expect(Money.sum(d.lines.map((x) => x.amount)), Money.kr(6586));
    });

    test('the footer adds nothing, the print date is not offered', () {
      expect(d.lines.length, 7);
      expect(d.date.value, '2026-11-02');
      expect(d.otherDates, isEmpty);
    });
  });

  group('Z-report 3 November', () {
    final d = _z(_nov3);

    test('the total stays 9 261,00, not the amount excluding VAT', () {
      expect(d.total.value, Money.kr(9261));
      expect(d.date.value, '2026-11-03');
      expect(d.zNumber.value, 'Z1-184');
    });

    test('the misread footer is no row, sprit keeps 363,00', () {
      expect(d.lines.map((l) => l.label), isNot(contains(startsWith('Veports'))));
      expect(d.lines.firstWhere((l) => l.label == 'sprit').amount, Money.kr(363));
      expect(d.lines.firstWhere((l) => l.label == ZLine.unnamed).amount, Money.kr(3716));
      expect(Money.sum(d.lines.map((l) => l.amount)), Money.kr(9261));
    });
  });

  test('the footer address onslip360 is never a sale of 360', () {
    final d = _z('Z-rapport\nPeriodens försäljning 150,00 kr\nFörsäljning per varugrupp\nMat 100,00 kr\nOs /lonslip 360\nslonsip 360\nTobak 50,00 kr');
    expect(d.lines.map((l) => l.label), ['Mat', 'Tobak']);
  });

  test('a shift that only gets closer is not used', () {
    final ocr = _columns([
      ('Z-rapport', null),
      ('Periodens försäljning', '1 000,00 kr'),
      ('Försäljning per varugrupp', null),
      ('Mat', '100,00 kr'),
      ('Tobak', '200,00 kr'),
      ('Cider', '300,00 kr'),
    ]);
    final d = const ZReportParser(_cats).parse(ocr);
    expect(d.total.value, Money.kr(1000));
    expect(d.lines.firstWhere((l) => l.label == 'Mat').amount, Money.kr(100));
    expect(d.lines.firstWhere((l) => l.label == 'Cider').amount, Money.kr(300));
  });

  test('with no total line, card and cash give the day', () {
    final d = _z('Z-rapport\nKort\nx 78   8444,00 kr\nKontanter\nx8   817,00 kr\nFörsäljning per varugrupp\nMat 9 261,00 kr');
    expect(d.total.value, Money.kr(9261));
    expect(d.total.confidence, Confidence.medium);
  });

  group('Sideways paper', () {
    OcrResult sideways(String text, {required bool tall}) {
      final box = tall ? OcrBox(0, 0, 20, 400) : OcrBox(0, 0, 400, 20);
      final l = OcrLine(text, box);
      return OcrResult(text: text, blocks: [OcrBlock(text, box, [l])]);
    }

    test('text running up the page is noticed', () {
      const long = 'INBETALNING GIRERING AVI Småföretagarnas Arbetslöshetskassa Oss tillhanda senast';
      expect(sideways(long, tall: true).looksSideways, isTrue);
      expect(sideways(long, tall: false).looksSideways, isFalse);
    });

    test('rotating swaps width and height', () {
      final jpeg = img.encodeJpg(img.Image(width: 40, height: 20));
      final turned = img.decodeJpg(rotateJpeg(PreprocessRotate(jpeg, 90)))!;
      expect((turned.width, turned.height), (20, 40));
    });
  });

  test('giro slip: amount without a label, payee, due date, OCR', () {
    final d = const InvoiceParser().parse(OcrResult.fromPlainText('''
INBETALNING/GIRERING AVI
Betalningsavsändare
Avinr: 31667970
Oss tillhanda senast: 2026-11-30
OCR: 5625620595
Till Bankgiro   Betalningsmottagare
126-2500   Småföretagarnas Arbetslöshetskassa
VAR GOD GÖR INGA ÄNDRINGAR
5625620595 #   159 00   4 >   1262500#41#
BG 130 OCR spec'''));
    expect(d.total.value, Money.kr(159));
    expect(d.total.confidence, Confidence.medium);
    expect(d.vatTotal.value, Money.zero);
    expect(d.vatTotal.confidence, Confidence.medium);
    expect(d.notes, isEmpty);
    expect(d.supplier.value, 'Småföretagarnas Arbetslöshetskassa');
    expect(d.dueDate.value, '2026-11-30');
    expect(d.ocrReference.value, '5625620595');
    expect(d.invoiceNumber.value, '31667970');
    expect(d.payment!.kind, PaymentKind.faktura);
  });
}
