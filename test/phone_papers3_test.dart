import 'package:bokforing/domain/invoice_parser.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/payment_detector.dart';
import 'package:bokforing/domain/text_patterns.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:flutter_test/flutter_test.dart';

InvoiceDraft _inv(String text) => const InvoiceParser(ownName: 'TWINS').parse(OcrResult.fromPlainText(text));

/// The owner's real papers, as the phone read them.
const _centrum = '''
FAKTURA
Fakturanr 138821
Kundnr 999   Sida   1
2026-10-22.
Vänligen ange fakturanummer vid betalning
CENTRUMGROSSISTEN AB
TWINS
PROVVÄGEN 12
Kvarngatan 2
123 45 Malmö   123 45 MALMÖ
Kontant
Förfallodatum   Leveranstid   Ordernr
2026-10-22
20261022   60468
Vid betalning efter ovanstående förfallodatum
Er Referens:   debiterar vi 12% dröjsmålsränta
Ant. Koli   Antal Enh Apris   Belopp   Beskrivning
sVAMP CHAMPINJON PL X3KG   1   3,00 KG   32,00   96,00
ISBERG SVENSK "VÁGES" RB   3,40 KG   20,03   68,10
LÖK RÒD IMP X12KG RB   7,00 KG   12,02   84,14
GURKA FILM SVENSK X12KG RB   1,10 KG   28,04   30,84
0,60 KG   38,55   23,13
GURKA SNACK SE X4KG
BETALD
2026 -1922
302,22
18,11
Innehar F-Skattsedel   Momspliktigt belopp   0,00
Moms 6%   -0,33
Orgnr:   556628-9285   Moms 25%   320,00
Bankgiro:   Öresutj.
439-9093
Telefonnr:   Att betala SEK
040-185310
Faxnr.
040-185318''';

const _snabbgross = '''
Snabbgross
KÖPNOTA Nr: 85721 Sida: 2 (2)
Datum: 2026-10-22
Tid: 16:50
Axfood Snabbgross AB   Kund:   390875L
Org.nr: 556000-3575   ANKAN RESTAURANG & PIZZ.
Certifierad: SE-EKO-06   PROVVÄGEN 12
Lundavägen 150, 123 45 Mal m8   12345 MALMÖ
Telefon: 040-680 6380
Säljare: 44039   Kassa: 1
Artikelnunmer   M Varubenämning   Rörp   Antal   à-pris   Pris   Rabatt
Moms 8   VARUVÄRDE   Moms   TOTALT
Moms kod Redu. . 6,00   4685,79   281,13   4966,92
Moms kod Stan. . 25,00   381,60   95,40   477,00
toTALER   5067,39   376,53   5443,92
Tot al rabatt:   3157,08KR
Våra öppettider är Mån-Fre: 06:00-20:00
Lördag: 07:00-17:00 Söndag: 07:00-17: 00
Vid retur & reklamation medhav giltigt kvitto
Inga returer på kyl eller frysvaror
En kvalitetsgaranti för dig s om kund
www. snabbgross.se''';

const _united = '''
UNITED GROSs   Kontantnota   Sida. 1
Vid betalning ange fakturanr/OCR: 114865389
Bankgiro: 5898-5912
Leveransadress
Fakturaadress
Twins Video& Pizzeria   Twins Video&Pizzeria
Lundaväaen 71   Provvägen 12
123 45 MALMÖ   (Besöksadress)
123 45 Malmö
Sverige
Kund nr   10000   Fakturadatum   2026-10-23
Ent ordermr   Betald med kort
Er referens
Vár referens
Vart ordernr   737528967   Ert momsreanr   SE121212121201
Prod.nr   Benämnina   Ant Enhet   Pris   Pris st   Tidigare oris   Rab.%   Belooo
12536   Kyck Sallad CP 2Kg*5   1 Förp   975.00   195,.00   975,00
OCR: 114865389   Belopp (SEK): 1 034,00
Bankgiro: 5898-5912
Frakt   Summa   975.00
Totalrabatt %   Moms 25% (0.00)   0.00
Besök vår nya hemsida: www.unitedaroSs.com
Moms 12% (0.00)   0.00
Pant:
Nu med webbshop!   Moms 6% (975,00)   5850
Avrundning   050
Eventuella anmarkninaar på fakturan skall delaes 8 dacar efter fakturadatu.   Att betala SEK   1034,00
Aaanderätten till varorna forblir saliarens tilis full betainina skett
E-mailadress   Godkand fôr F-skatt
Telefon
United Gross i Sverige AB
040-947 690   order@unitedaross com   VAT reg nr
Bariumgatan 14   internet adress
SE55679227 1001
213 64 MALMO
www.unitedarosS.com''';

const _ikea = '''
OKEA
IKEA MALMÖ
Kulthusgatan 1, 21586 Mal mö
IKEA Fami ly k 6275980xXXxXXXX5709
Art/EAN 30548871   22846
RÖDALM ram 13x18 val   39,00
Art/EAN 40510839   17312   263
FIKADAGS vispskàl 2.   9,00
Art/EAN 30083334   22458
GRUNKA köksredskap 4   99,00   0
Art/EAN 70619017
HAVSTULPAN pizzaskär   20615
2 * 39,00
Art/EAN 10428488 qoe,u
FÖRNUFT kniv 21 rost 22185
2 * 25,0050,00 0
Art/EAN 40428482 b i0 5X6diU enspn90
FÖRNUFT gaffel 19 ro 22185
2 * 25,00sben 50,00
Art/EAN 50035752   dblislondrsbn
FANTASTISK pappserv 19394
10 *   29.00   290,00 0
Total   615,00
Totalt artiklar:   19
EFT MASTER   615,00 SEK
SEPA-FAST
KONTAKTLÖS
Kul thusgatan 1 Malm0 21586
000002101858960
00000002 gldosq spnl Spib ietpnb ub sH
A0000000041010 ub mo lsdlid etspnsg,
Debit Mastercard
XXXXXXXXXXXX9236 00 6veso 6ney do,
24/10/2026d 14:59:476otu Sle oloD
249896emeil   445247   0p0y sbl6tesdtbe.
BELOPP   615,00 SEK
PIN VERIFIERAD
KÖP GODKÄNT
KORTINNEHAVARENS   KVITTO
POS TRX ID: 20261024/445/41/40
Moms:   KURS   NETTO   MOMS
KOD   %492,00123,00
0 25,0
41 1
Kassörnummer:   VH   Ka Tr
Datum Tid   445 4140
26.10.24 15:00: 00
Org. nr. 556074-7569
Öppet Man-Fre 10-20 Lör-Sön 10-19
0775-700 500
Har du testat expressretur?o
https://www. i kea.com/se/sv/returns
990044500410004026102 4''';

const _eon = '''
eon   Faktura - Privatkund elnät
E.ON Kun dsupport Sverige AB
601 71 Norrköping
Robert Khanian
Provvägen 12 A 1   21200
123 45 Malmö
Belopp att betala   1936 kr
Dina betalnings-   Betala senast   28 oktober 2026
Bankgiro   5014-0045
uppgifter   Faktura/OCR-nummer   265 896 994 17
Avser   september 2026
tos 378,6
Kundnummer   3000000
Kontakta oss
Läs om dina rättigheter och vart du vänder dig om du inte är nöjd på eon.se
bankgirot   INBETALNING/GIRERING AVI
TInbet avgift (ifylls av banken)
OCR
Betala senast 2026 10 28
Robert Khanian
Provvägen 12 A l
123 45 Malmö
Till bankgiro   Betalningsmottagare
5014-0045   E.ON Kundsupport Sverige AB
DEN AVLÄSES MASKINELLT
MEDDELANDEN KAN INTE LÄMNAS PÅ AVIN
VAR GOD GÖR INGA ÄNDRINGAR
OCR-nummer   | Syenska kronor   | öre
50140045#41#
1936 00   4 >
26589699417 #
2025 Arsförbrukning 17 388 kWh
2026 Hittills 12 887 kWh (förra året 13 232 kWh)
Prognos för hela 2026: 17 044 kWh
Kundnummer 3000000   Det här betalar du för
20 A, Elnätsområde Syd   Elnätsabonnemang månadsavgift, 656 kr
Annan leverantör   Elöverföring, 1 443 kWh à 25,84 öre   656/
Provvägen 12A, 123 45 Malmö   Energiskatt, 1 443 kWh à 36,00 öre   372,98 kr
3 oktober 2026   519,64 kr
Totalt E.ON Energidistribution AB 1548,62 kr
735 999 114 003 814 710   Summa exkl moms
MMO   Moms 25%   1548.
C4   Öresutjämning   387,15 kr
4   0,22 kr
Belopp att betala
505 163 960 875 3309   1936,00 kr
Mätarställning   Förbrukning
61 882
63 325
1 443 kWh''';

void main() {
  test('Centrumgrossisten: amounts two rows off, bankgiro is not the total', () {
    final d = _inv(_centrum);
    expect(d.total.value, Money.kr(320));
    expect(d.vatTotal.value, const Money(1811));
    expect(d.vatLines.single.rate, VatRate.six);
    expect(d.net, const Money(30222));
    expect(d.date.value, '2026-10-22');
    expect(d.dueDate.value, '2026-10-22');
    expect(d.invoiceNumber.value, '138821');
    expect(d.supplier.value, 'CENTRUMGROSSISTEN AB');
  });

  test('Snabbgross: VAT table with Varuvärde, "Moms 8" is a heading', () {
    final d = _inv(_snabbgross);
    expect(d.vatTotal.value, const Money(37653));
    expect(d.vatLines.length, 2);
    expect(d.total.value, const Money(544392));
    expect(d.total.confidence, Confidence.high);
    expect(d.net, const Money(506739));
    expect(d.supplier.value, 'Axfood Snabbgross AB');
    expect(d.invoiceNumber.value, '85721');
    expect(d.payment!.kind, PaymentKind.kvitto);
    expect(d.payment!.paid, isTrue);
  });

  test('United Gross: "5850" is 58,50, Kontantnota is paid', () {
    final d = _inv(_united);
    expect(d.total.value, Money.kr(1034));
    expect(d.total.confidence, Confidence.high);
    expect(d.vatTotal.value, const Money(5850));
    expect(d.vatLines.single.rate, VatRate.six);
    expect(d.net, Money.kr(975));
    expect(d.date.value, '2026-10-23');
    expect(d.invoiceNumber.value, '114865389');
    expect(d.supplier.value, 'United Gross i Sverige AB');
    expect(d.payment!.kind, PaymentKind.kvitto);
    expect(d.payment!.paid, isTrue);
  });

  test('IKEA: year first date, stuck amounts, misread logo', () {
    final d = _inv(_ikea);
    expect(d.date.value, '2026-10-24');
    expect(d.total.value, Money.kr(615));
    expect(d.total.confidence, Confidence.high);
    expect(d.vatTotal.value, Money.kr(123));
    expect(d.vatLines.single.rate, VatRate.twentyFive);
    expect(d.supplier.value, 'IKEA');
    expect(d.payment!.kind, PaymentKind.kvitto);
  });

  test('E.ON: VAT is not the net above it, due date, OCR with spaces', () {
    final d = _inv(_eon);
    expect(d.total.value, Money.kr(1936));
    expect(d.total.confidence, Confidence.high);
    expect(d.vatTotal.value, const Money(38715));
    expect(d.net, const Money(154862));
    expect(d.date.value, '2026-10-03');
    expect(d.dueDate.value, '2026-10-28');
    expect(d.ocrReference.value, '26589699417');
    expect(d.invoiceNumber.value, '26589699417');
    expect(d.bankgiro.value, '5014-0045');
    expect(d.supplier.value, 'E.ON Kun dsupport Sverige AB');
    expect(d.payment!.kind, PaymentKind.faktura);
  });

  group('Reading rules', () {
    test('short dates: the reading closest to today wins', () {
      expect(TextPatterns.dates('26.10.24'), ['2026-10-24']);
      expect(TextPatterns.dates('Betala senast 2026 10 28'), ['2026-10-28']);
    });

    test('two recent readings are marked as uncertain', () {
      final now = DateTime.now();
      final y = now.year % 100;
      final month = now.month.toString().padLeft(2, '0');
      expect(TextPatterns.hasAmbiguousDate('$y.$month.${y - 1}'), isTrue);
      expect(TextPatterns.hasAmbiguousDate('2026-10-24'), isFalse);
    });

    test('giro, org and phone numbers are never amounts', () {
      expect(TextPatterns.amounts('439-9093'), isEmpty);
      expect(TextPatterns.amounts('556628-9285'), isEmpty);
      expect(TextPatterns.amounts('040-185310'), isEmpty);
      expect(TextPatterns.amounts('0775-700 500'), isEmpty);
    });

    test('a separator lost in the VAT amount is repaired from the base', () {
      final d = _inv('Faktura\nMoms 25% (100,00)   2500\nAtt betala   125,00');
      expect(d.vatTotal.value, Money.kr(25));
      expect(d.total.value, Money.kr(125));
    });
  });
}
