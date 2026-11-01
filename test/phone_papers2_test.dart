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

InvoiceDraft _inv(String text) => const InvoiceParser(ownName: 'TWINS').parse(OcrResult.fromPlainText(text));

/// The owner's real papers, as the phone read them.
const _willys = '''
WiLLY:S
Vår affärsidé: Sveriges billigaste matkasse
Tel 040-6803440
Org : 556163-2232
Totalt 9 varor
Öresavrundnin9   0,18
Totalt   198, OO SEK
Mottaget Kontant   200,00
Ater   Kontant   -2,00
Moms%   Moms   Netto   Brutto
6,00   11,20   186,62   197,82
SPARA KVITTOT
Kassa: 3701   2026-10-07 20:08''';

const _nassim = '''
Kvitto
Nassim
Kvittonr   Kundnr   Datum
11519   1912   26-10-07   10.04   Sidnr
Leveransadress   Faktureringsadress
Ankan pub & pizzeria   Ankan pub & pizzeria
Lundav. 71   Lunday. 71
123 45 Malmö   123 45 Malmö
Ert ordernr   Leveransdatum   2026-10-07
Er referens   Herr Ali   Säljare   Afsaneh
Kontant   706.00
Netto   665.81
Moms 25% ()   0.00   Expeditionsavgift
0.00
Moms 6% (665.81)   39.95   0.00
Total rabatt   0.00   Fraktavgift   39.95
Moms
0.24
overlats   Öresutj
fakturan til PS Inkasso   elseavgift och
räntelagen, med referensrantan   706.00
Påminnels   Att betala SEK
Nassim AB   556654-4507   IP A
Bankgiro   CERTIFIERAD''';

const _inbev = '''
OABİnBev
AB InBev Sweden
11160 Stockholm   Faktura
Nr:   Original
TEL : + 46 (0) 8 446 897 S6   9003790916
Datum:   24.09,2026
Moms Nr SE559 145624801
Betalare   ANKAN RESTAURANG AB
Leveransdatum   23.09.2026   Mottagare
Moms Nr   : SE65072 7297601   LUNDAVAGEN
Betalningsvillkor   : 15 Dagar   12345
Nettobelop| Rabatt   Nettobelopp   Moms
Summa exkl moms
15.808,60
MS   3.952,15
25,00 % av   15.808,60
Gumma totalt:   19.760,75
Förfallodatum 09/10/2026
Holländargatan 17   Moms Nr SE559 145624801
/ 5591456248 / BANKGIRO 5007-2008''';

const _kredit = '''
KO ABInBev
AB InBev Sweden
Holländargatan 17   Kreditnota
EMAIL : KUNDCENTER@AB-INBEV.CcOM   Nr:
9003796683   Original
TEL :+ 46 (0) 8 446 897 56   Datum:
28.09.2026
Moms Nr SES59 14562480 1
Betalare   30000000   ANKAN RESTAURANG AB
Pan   12   0,00   500,00   6.000,00   25
7.500,00
P1514   KEG NORDICS GENERIC
6.000,00
Summa exkl moms
1.500,00
MOMS:   25,00% av   6.000,00
7.500,00
Summa totalt:   Vänligen dra av den här
krediten vid er nästa betalning
Moms Nr SES59 145624801 / 5591456248 /
BANKGIRO 5007-2008
AB InBev Sweden''';

void main() {
  test('the cleaned image is grey, not red', () {
    final photo = img.Image(width: 400, height: 500);
    img.fill(photo, color: img.ColorRgb8(40, 40, 40));
    img.fillRect(photo, x1: 60, y1: 60, x2: 340, y2: 440, color: img.ColorRgb8(240, 240, 240));
    final out = img.decodeJpg(preprocessDocument(PreprocessRequest(img.encodeJpg(photo))).jpeg)!;
    final p = out.getPixel(out.width ~/ 2, out.height ~/ 2);
    expect((p.r - p.g).abs(), lessThan(8));
    expect((p.r - p.b).abs(), lessThan(8));
    expect(p.g, greaterThan(150));
  });

  test('Willys: 198,00 despite "198, OO", change word misread', () {
    final d = _inv(_willys);
    expect(d.total.value, Money.kr(198));
    expect(d.total.confidence, Confidence.high);
    expect(d.vatTotal.value, const Money(1120));
    expect(d.date.value, '2026-10-07');
  });

  test('Nassim: date, total from nearby amount, supplier, kvitto', () {
    final d = _inv(_nassim);
    expect(d.date.value, '2026-10-07');
    expect(d.total.value, Money.kr(706));
    expect(d.total.confidence, isNot(Confidence.low));
    expect(d.vatTotal.value, const Money(3995));
    expect(d.supplier.value, 'Nassim AB');
    expect(d.invoiceNumber.value, '11519');
    expect(d.payment!.kind, PaymentKind.kvitto);
  });

  test('AB InBev: VAT number is not VAT, comma date, invoice number', () {
    final d = _inv(_inbev);
    expect(d.total.value, const Money(1976075));
    expect(d.vatTotal.value, const Money(395215));
    expect(d.vatLines.single.rate, VatRate.twentyFive);
    expect(d.net, const Money(1580860));
    expect(d.date.value, '2026-09-24');
    expect(d.dueDate.value, '2026-10-09');
    expect(d.supplier.value, 'AB InBev Sweden');
    expect(d.invoiceNumber.value, '9003790916');
    expect(d.bankgiro.value, '5007-2008');
    expect(d.payment!.paid, isFalse);
  });

  test('AB InBev kreditnota: amounts above their labels, VAT from the base', () {
    final d = _inv(_kredit);
    expect(d.isCredit, isTrue);
    expect(d.total.value, const Money(-750000));
    expect(d.vatTotal.value, const Money(-150000));
    expect(d.vatLines.single.vat, const Money(-150000));
    expect(d.date.value, '2026-09-28');
    expect(d.invoiceNumber.value, '9003796683');
  });

  group('Short dates', () {
    test('year first with dashes, day first with slashes', () {
      expect(TextPatterns.dates('26-10-07'), ['2026-10-07']);
      expect(TextPatterns.dates('26-10-09 23:59'), ['2026-10-09']);
      expect(TextPatterns.dates('09/10/26'), ['2026-10-09']);
      expect(TextPatterns.dates('24.09,2026'), ['2026-09-24']);
    });
  });

  group('Z-report with the amount column one line off', () {
    const cats = [
      Category(id: 1, name: 'Mat', vat: VatRate.twelve),
      Category(id: 2, name: 'Vin', vat: VatRate.twentyFive),
      Category(id: 3, name: 'Öl', vat: VatRate.twentyFive),
    ];
    OcrLine line(String t, double left, double top, double w) => OcrLine(t, OcrBox(left, top, left + w, top + 20));

    test('names and amounts pair up when the rows then match the total', () {
      // Amounts sit 30 px (one row) lower than their names.
      final lines = [
        line('Z-rapport', 50, 0, 200),
        line('Periodens försäljning', 50, 60, 240),
        line('Periodens försäljning exkl moms', 50, 90, 300),
        line('14 239,00 kr', 800, 90, 120),
        line('11 842,74 kr', 800, 120, 120),
        line('Försäljning per varugrupp', 50, 180, 280),
        line('Mat', 50, 210, 60),
        line('Vin', 50, 240, 60),
        line('Öl', 50, 270, 60),
        line('5 000,00 kr', 800, 240, 110),
        line('239,00 kr', 800, 270, 100),
        line('9 000,00 kr', 800, 300, 110),
      ];
      final ocr = OcrResult(text: '', blocks: [for (final l in lines) OcrBlock(l.text, l.box, [l])]);
      final d = const ZReportParser(cats).parse(ocr);
      expect(d.total.value, Money.kr(14239));
      ZLine row(String l) => d.lines.firstWhere((x) => x.label == l);
      expect(row('Mat').amount, Money.kr(5000));
      expect(row('Vin').amount, Money.kr(239));
      expect(row('Öl').amount, Money.kr(9000));
    });

    test('a line one letter off the own rule counts automatically', () {
      final d = const ZReportParser(cats, aliases: {'drycka avhämtning': 1}).parse(OcrResult.fromPlainText(
          'Z-rapport\nVarugrupper\nDrycka avhäntning 70,00\nTotal försäljning 70,00'));
      expect(d.lines.single.categoryId, 1);
      expect(d.lines.single.match, MatchKind.remembered);
    });
  });
}
