import 'package:bokforing/domain/invoice_parser.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/payment_detector.dart';
import 'package:bokforing/domain/slip_code_line.dart';
import 'package:bokforing/domain/text_patterns.dart';
import 'package:flutter_test/flutter_test.dart';

/// Papers from the owner's test round of 2026-11-07 (97 photos), cut down to
/// the rows that were read wrong.
InvoiceDraft _read(String text, {String ownName = ''}) =>
    InvoiceParser(ownName: ownName).parse(OcrResult.fromPlainText(text));

void main() {
  test('Total: the amount after "Att betala", not the subtotal before it', () {
    final d = _read('''
AXFOOD SNABBGROSS
Kvitto
ANTAL ART. 14   SUBTOTAL 1891,76   ATT BETALA 1892,00
KORT   1892,00''');
    expect(d.total.value, Money.parse('1892,00'));
  });

  test('Total: label printed after the amounts takes the next row', () {
    final d = _read('''
Tobakskompaniet
Faktura
Moms 25%   1 916,20   (7 664,80)   Belopp att betala
9 581,00''');
    expect(d.total.value, Money.parse('9581,00'));
    expect(d.vatTotal.value, Money.parse('1916,20'));
  });

  test('Total: TOTALER alone takes an amounts-only row, never "Total rabatt"', () {
    final d = _read('''
SNABBGROSS
TOTALER
5 067,39   376,53   5 443,92
Total rabatt   42,60
KORT   5 443,92''');
    expect(d.total.value, Money.parse('5443,92'));
  });

  test('VAT table: a rate glued to dots ("Stan..25,00") is read', () {
    final d = _read('''
Grossist
Momssats   Exkl moms   Moms   Inkl moms
Stan..25,00   1 000,00   250,00   1 250,00
Livs..12,00   500,00   60,00   560,00
Att betala   1 810,00''');
    expect(d.vatLines.length, 2);
    expect(d.vatTotal.value, Money.parse('310,00'));
    expect(d.total.value, Money.parse('1810,00'));
  });

  test('VAT table: VAT summed from item lines may be a few öre off the rate', () {
    final d = _read('''
Grossist
Momssats   Exkl moms   Moms   Inkl moms
6,00   2 792,93   167,53   2 960,46
Att betala   2 960,46''');
    expect(d.vatLines.length, 1);
    expect(d.vatTotal.value, Money.parse('167,53'));
  });

  test('A sum row net + VAT = gross beats a misread "Moms" row', () {
    final d = _read('''
Tre
Faktureringsdag   2026-10-20
Moms   1 124,20
Summa   1 124,20   233,55   1 357,75
Att betala   1 357,75''');
    expect(d.vatTotal.value, Money.parse('233,55'));
    expect(d.total.value, Money.parse('1357,75'));
    expect(d.date.value, '2026-10-20');
  });

  test('Two VAT rates add up to the total; a crumb "Moms 0,02" is not the VAT', () {
    final d = _read('''
osT AB
2026-10-16
Fakturadatum
Förfallodatum   2026-11-15
Mat 6%   16 758,00   1 005,48
Dryck 25%   398,00   99,50
Netto   17 156,00
Summa   0,02
Moms   0,02
Att betala   18 261,00
Rest Lillebror Öst AB   Org.nr 559012-3456''');
    expect(d.total.value, Money.parse('18261,00'));
    expect(d.vatTotal.value, Money.parse('1104,98'));
    expect(d.vatLines.length, 2);
    expect(d.date.value, '2026-10-16');
    expect(d.dueDate.value, '2026-11-15');
    expect(d.supplier.value, 'Rest Lillebror Öst AB');
  });

  test('Unreadable VAT is calculated from net and total, and flagged', () {
    final d = _read('''
AB InBev Sverige
Fakturadatum   2026-10-08
Summa exkl. moms   17 237,08
Moms   928,47
Att betala   21 546,35''');
    expect(d.total.value, Money.parse('21546,35'));
    expect(d.vatTotal.value, Money.parse('4309,27'));
    expect(d.vatTotal.confidence, Confidence.medium);
  });

  test('A dot for the decimal comma after a thousands dot', () {
    expect(OcrResult.cleanOcrText('Moms   4.309.27'), 'Moms   4.309,27');
    expect(OcrResult.cleanOcrText('2026.10.27'), '2026.10.27');
  });

  test('Dates: misread due label, and the invoice date two rows down', () {
    final d = _read('''
SAMI
Fakturadatum
Kundnummer
2026-10-05
Förtallodatum   2026-11-04''');
    expect(d.date.value, '2026-10-05');
    expect(d.dueDate.value, '2026-11-04');
  });

  test('Invoice number: not the VAT number, and found on the row below', () {
    final d = _read('''
Tobakskompaniet
VAT nr: SE559093862601
Fakturanummer
Faktura   160614''');
    expect(d.invoiceNumber.value, '160614');
  });

  test('OCR: never an amount, a bankgiro check line, or a cut number', () {
    expect(_read('''
Lifra
OCR   17396,00''').ocrReference.hasValue, isFalse);
    expect(_read('''
SAMI
OCR   1185#41#''').ocrReference.hasValue, isFalse);
    expect(_read('''
United Gross
OCR   11488854
#   114888548 #   4 >''').ocrReference.value, '114888548');
    expect(_read('''
Leverantör AB
Referensnummer   12345678901''').ocrReference.value, '12345678901');
  });

  test('Bankgiro below its label; payee label with a note in brackets', () {
    final d = _read('''
Securitas
Till bankgironr
Belopp
253-6761
Betalningsmottagare (endast namn)
Securitas Sverige AB''');
    expect(d.bankgiro.value, '253-6761');
    expect(d.supplier.value, 'Securitas Sverige AB');
  });

  test('Telenor: name with "tel", number under "Fakturanummer/OCR"', () {
    final d = _read('''
telenor
Ankan restaurang & pizzeria
Östra Provgatan 1B Lgh 12
123 45 Malmö
Faktura
Gäller rörliga avgifter för perioden
2026-07-16 till 2026-10-15
uppkoppling - det är   Fakturanummer/OCR
526730297326
Fakturadatum   2026-10-16
arbeta säkert, effektivt och   PlusGiro
4792603-5
flexibelt.   Kundnummer   10000000-01
VAT-nummer   SE121212121201
uppkoppling via vårt 5G nät som   Att betala   1433,00 kr
som minskar risken för   Varav moms   286,50 kr
får ni stöd för smidigt   Oss tillhanda senast   2026-11-15
digital arbetsmiljö som   0770-777 777''', ownName: 'Ankan restaurang & pizzeria');
    expect(d.supplier.value, 'telenor');
    expect(d.total.value, Money.parse('1433,00'));
    expect(d.vatTotal.value, Money.parse('286,50'));
    expect(d.date.value, '2026-10-16');
    expect(d.dueDate.value, '2026-11-15');
    expect(d.invoiceNumber.value, '526730297326');
    expect(d.ocrReference.value, '526730297326');
    expect(d.plusgiro.value, '4792603-5');
    expect(d.isCredit, isFalse);
  });

  test('"Rabatter & Krediteringar" on a specification page is no kreditnota', () {
    final d = _read('''
Telenor
Specifikation
Rabatter & Krediteringar   -50,00
Att betala   1433,00''');
    expect(d.isCredit, isFalse);
  });

  test('A card receipt for "Betalning av faktura" is paid', () {
    final p = const PaymentDetector().detect([
      'Tobakskompaniet',
      'Betalning av faktura',
      'Fakturanummer 160614',
      'Kortnr ************1234',
      'Godkänd',
      'Belopp 9 581,00',
    ]);
    expect(p.kind, PaymentKind.kvitto);
    expect(p.paid, isTrue);
  });

  test('A giro slip amount alone on its row, beside the code line', () {
    final d = _read('''
Inbetalning/Girering AVI
SMÅA
159 00
#   12345678   #   4 >''');
    expect(d.total.value, Money.parse('159,00'));
    // No moms on a giro slip: a 0 % row, so the saved invoice is not "missing moms".
    expect(d.vatTotal.value, Money.zero);
    expect(d.vatLines.single.rate.basisPoints, 0);
  });

  test('Rows read right to left look upside down', () {
    final r = OcrResult.fromPlainText('''
5443,92   376,53   5067,39   TOTALER
42,60   RABATT
1892,00   KORT
120,00   MAT''');
    expect(r.looksUpsideDown, isTrue);
    expect(OcrResult.fromPlainText('''
TOTALER   5067,39   376,53   5443,92
RABATT   42,60
KORT   1892,00''').looksUpsideDown, isFalse);
  });

  test('Slip code line: OCR, amount and bankgiro with check digits', () {
    expect(SlipCodeLine.luhnValid('1234567897'), isTrue);
    expect(SlipCodeLine.luhnValid('1234567898'), isFalse);
    final d = _read('''
Leverantören AB
OCR   1234567891
Att betala   195,00
Bankgiro   5050-1056
#   1234567897   #   159 00   4 >   50501055#41#''');
    expect(d.ocrReference.value, '1234567897');
    expect(d.total.value, Money.parse('159,00'));
    expect(d.total.confidence, Confidence.high);
    expect(d.bankgiro.value, '5050-1055');
  });

  test('Slip code line with a failed check digit changes nothing', () {
    final d = _read('''
Leverantören AB
OCR   1234567897
Att betala   159,00
#   1234567890   #   195 00   4 >   50501056#41#''');
    expect(d.ocrReference.value, '1234567897');
    expect(d.total.value, Money.parse('159,00'));
  });

  test('The logo name backs up a guessed supplier', () {
    OcrLine line(String t, double top, double height) => OcrLine(t, OcrBox(0, top, t.length * 10.0, top + height));
    final lines = [
      line('Tack för ditt köp', 0, 14),
      line('ELKEDJAN', 20, 60),
      line('Faktura', 80, 16),
      line('Kund: Ankan restaurang', 100, 16),
      line('Fakturadatum   2026-10-20', 120, 16),
      line('Att betala   500,00', 400, 16),
      line('Varav moms   100,00', 420, 16),
    ];
    final r = OcrResult(text: '', blocks: [for (final l in lines) OcrBlock(l.text, l.box, [l])], imageWidth: 1000, imageHeight: 600);
    final d = const InvoiceParser(ownName: 'Ankan restaurang').parse(r);
    expect(d.supplier.value, 'ELKEDJAN');
  });
}
