import 'package:bokforing/domain/invoice_parser.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/online_parser.dart';
import 'package:bokforing/domain/text_patterns.dart';
import 'package:flutter_test/flutter_test.dart';

/// Papers from the owner's test of 2026-11-08, as the phone read them.
InvoiceDraft _read(String text, {String ownName = 'Ankan restaurang & pizzeria'}) =>
    InvoiceParser(ownName: ownName).parse(OcrResult.fromPlainText(text));

void main() {
  test('Snabbgross: VAT table with a misread TOTALER row gives both rates', () {
    final d = _read('''
Snabbgross   KÖPNOTA NE: 105017 sida: 1 (1)
Datum: 2026-11-07
Axfood Snabbgross AB
ANTAL ART.   11   SUBTOTAL   1053,58   ATT BETALA   1054,00
Mottaget   Kontant   1110,00
Äter   Kontant   -56,00
Moms 8   VARUVÄRDE   Moms   TOTALT
Moms kod   Redu. . 6,00   959,88   57,57
1017,45
Momskod   Stan..25,00
28,90   7,23   36,13
roTALER   988,78   64,80   1053,58
Total rabatt:   77,00KR''');
    expect(d.total.value, Money.parse('1054,00'));
    expect(d.vatTotal.value, Money.parse('64,80'));
  });

  test('Giro slip: the code line without ">" still gives amount and bankgiro', () {
    final d = _read('''
bankoirot   INBETALNINGIGIRERING AVI
OCR
Betalningsavsändare   Avinr: 31698117
Robert Khanian   Oss tillhanda senast:
2026-12-31
123 45 Malmö   OCR: 5625620595
Bankgironr   Betalningsmottagare
126-2500   Småföretagarnas
Arbetsiöshetskassa
VAR GOD GÖR INGA ANDRINGAR   MEDDELANDEN
Referensnr   Kronor   Töre
5625620595 #   159 00   4   1262500#41#''', ownName: '');
    expect(d.total.value, Money.kr(159));
    expect(d.total.confidence, Confidence.high);
    expect(d.bankgiro.value, '126-2500');
    expect(d.ocrReference.value, '5625620595');
    expect(d.dueDate.value, '2026-12-31');
  });

  test('Telenor: a zero read for O in "OCR" gives no invoice number "0"', () {
    for (final text in [
      'och fler cyberhot påverkar   Fakturanummer/0CR   526730297326',
      'och fler cyberhot påverkar   Fakturanummer/\n0CR   526730297326',
    ]) {
      final d = _read('''
telenor
Ankan restaurang & pizzeria
Faktura
$text
Fakturadatum   2026-10-16
PlusGiro   4792603-5
uppkoppling via vårt 56 nät som   Att betala   1433,00 kr
Varav moms   286,50 kr
får ni stöd för smidigt   Oss tillhanda senast   2026-11-15''');
      expect(d.invoiceNumber.value, '526730297326', reason: text);
      expect(d.ocrReference.value, '526730297326', reason: text);
      expect(d.dueDate.value, '2026-11-15');
    }
  });

  test('Fortnox: "Tillhanda senast" is the due date; OCR and bankgiro from the slip', () {
    final d = _read('''
Fakturan hanteras av Fortnox Finans AB
forgnr 556949-9824). Betalning rmed
Fortnox Finans AB   vel bankgironurmmer och
med korrekt referensnr (0CR) IBAN SE33 8000
0816 9569 4846 5262
gbankgirot   INBETALNING / GIRERING AVI
Så betalar du   Betalningsavsändare
Att betala:   9 581,00 SEK   Ankan
Till Bankgiro:   5020-7042   Provvägen 12
Tillhanda senast:   2026-11-07   12345
0CR-nummer:   546812516989653   Sverige
Till bankgironr   Betalingsmottagare
|5020-7042   Fortnox Finans AB
VAR GOD GÖR INGA ÄNDRINGAR   MEDDELANDEN
Releensn   Kronos   Ore
S0207042#41#
H   546812516989653   9581 00''');
    expect(d.total.value, Money.parse('9581,00'));
    expect(d.dueDate.value, '2026-11-07');
    expect(d.ocrReference.value, '546812516989653');
    expect(d.bankgiro.value, '5020-7042');
  });

  test('Vattenfall: VAT worked out from the printed rate and net when the amount was not read', () {
    final d = _read('''
VATTENFALL
Kundnummer:   2000000001
Fakturanummer:   5230056291934
Fakturadatum:   2026-10-01
Faktura el
Belopp att betala:   838,76 kr
Oss tillhanda senast:   2026-10-28
Bankgiro:   5110-8348
Summa momspliktigt   Moms 25%
Fakturering   671,01 kr
VAR GOD GOR INGA ÄNDRINGAR   MEDDELANDEN
Krooor   Ore
52300562919341 #   838 76   3>   51108348
#41#''');
    expect(d.total.value, Money.parse('838,76'));
    expect(d.vatTotal.value, Money.parse('167,75'));
    expect(d.vatTotal.confidence, Confidence.medium);
    expect(d.ocrReference.value, '52300562919341');
    expect(d.bankgiro.value, '5110-8348');
  });

  test('Svekraft: values under a row of labels are taken from the same column', () {
    final d = _read('''
FAKTURA
Svekraft
Returadress: Svekraft AB
Box 126, 246 22 Loddeköpinge
Fakturadatum:   Förfallodag:   Ankan restaurang & pizzeria
2026-10-09   2026-10-27   Robert Khanian
Kundnummer.   OCR-nr:   Provvägen 12 A
612123   20000000000   12345 Malmö
Fakturanr.   Bankgironr.
20000000000   342-6830
Totalbelopp att betala:   1 203,00 kr
Varav moms
240,13 kr''');
    expect(d.date.value, '2026-10-09');
    expect(d.dueDate.value, '2026-10-27');
    expect(d.ocrReference.value, '20000000000');
    expect(d.invoiceNumber.value, '20000000000');
    expect(d.vatTotal.value, Money.parse('240,13'));
    expect(d.supplier.value, 'Svekraft AB');
  });

  test('Sam Grossist: the bank named in the footer is not the supplier', () {
    final d = _read('''
KONTANTNOTA
Sam   Fakturanummer   813873
Fakturadatum   2026-10-29
Grossist
Leveransadress   Twins Video
Provvägen 12
123 45 Malmö
Summa   2 555,00
Styrelsens säte   Org-nr   Telefon   Bankgiro
Malmö   556682-4925   040-62261   5582-3220
V.A.T-nr   Telefax   Bank: Swedbank AB''');
    expect(d.supplier.value, isNot('Swedbank AB'));
  });

  test('Foodora: a misread "Betalningsdatum" label still gives the date', () {
    final d = const OnlineParser().parse(OcrResult.fromPlainText('''
foodora   SE-112 26 Stockholm
Betalningsbekräftelse
Partner ID: ENQN
Dokumentnummner: 606007795280
Betainingsdatum:   26.10.2026
Totalt belopp   773,55
SEK
Betalt belopp   773,55'''));
    expect(d.date.value, '2026-10-26');
    expect(d.amount.value, Money.parse('773,55'));
  });

  test('A zero in "0CR" is read as the letter O', () {
    expect(OcrResult.cleanOcrText('0CR-nummer: 5468'), 'OCR-nummer: 5468');
    expect(OcrResult.cleanOcrText('Belopp 10CR'), 'Belopp 10CR');
  });
}
