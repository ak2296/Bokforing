import 'package:bokforing/data/database.dart';
import 'package:bokforing/data/repository.dart';
import 'package:bokforing/domain/invoice_parser.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/online_parser.dart';
import 'package:bokforing/domain/payment_detector.dart';
import 'package:bokforing/domain/reports.dart';
import 'package:bokforing/domain/text_patterns.dart';
import 'package:bokforing/domain/validation.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:bokforing/domain/z_report_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

OcrResult _ocr(String text) => OcrResult.fromPlainText(text);

/// The owner's real papers, as the phone read them.
const _centrum = '''
FAKTURA   Fakturanr   138956   Sida
Kundnr   999
2026-10-30
Vänligen ange fakturanummer vid betalning
CENTRUMGROSS ISTEN AB
TWINS
PROVVÄGEN 12
Kvarngatan 2
123 45 Malmö   123 45 MALMÖ
Kontant
Förfallodatum   Leveranstid   Ordernr
2026-10-30   20261030   60719
Vid betalning efter ovanstående
förfallodatum
Er Referens:   debiterar vi 12%
dröjsmålsränta
BEAD
2026 -10/3 0
Innehar F-Skattsedel
Momspliktigt belopp   491,87
Orgnr:   556628-9285   Moms 6%   29,47
Bankgiro:   439-9093   Moms 25%   0,00
Telefonnr:   040-185310   Oresut.   -0.34
Faxnr:   Att betala SEK   521,00''';

const _systembolaget = '''
Historiska bet
Systembolaget
Bur lövs Centrum
232 37 ARLÖV
+4640432420
OrgNr: 556059-9473
Kassa: 01 Nr: 6824
latum: 2026-10-29   Tid: 16:31
Antal varor   183 st
Total   4 31 1,30 kr
oms%   Moms   Netto Totalt
25,00   862,26   3449,04 43|1,30
lotalt   862,26 3449,04   4311,30
tottaget Kontokort Adyen   4311,30
Datum   2026-10-29
fotalt   SEK 4.311,30
iOdkänt
Sista dagen för återköp: 2026-11-28''';

const _zReport = '''
20:55
2026-10-31 13:20
Z-Rapport: Alla kassor (1 st)   2026-10-30 23:59
Från:   2026-10-30 11:29 Org.nr:   itaurang & pizzeria
Till:   2026-10-30 22:21 Tid:   jen 71 A212
Underlag: Z1-180
GENERELLT
Periodens försäljning   12 955,00 kr
Periodens försäljning exkl moms   10 782,79 kr
FORSALJNING PER VARUGRUPP EXKl
Drycka   163,00 kr
Drycka avhäntning
70,00 kr
Mat
1912,00 kr
Mat avhämtning
1 507,00 kr
Tobak
880,00 kr
sprit   2512,00 kr
Vin
89.00 kr
gi
öl
5 822,00 kr
or
https:/onslip360.corn/tt/reports/z-report
1/2''';

const _foodora = '''
Foodora AB
Bankgiro:5462-0000
PARTNER
Ankan restaurang & pizzeria
Betalningsbekräftelse
Partner ID: ENQN   Betalningdatum: 09.10.2026
Dokumentnummer: 634007945393
Nedan hittar du en lista med utförda betalningar.
Fakturanummer   Datum   Valuta   Belopp
7002848525   08.10.2026   SEK   2 001,14
Totalt belopp   SEK   2 001,14
Betalt belopp   SEK   2 001,14''';

void main() {
  group('Centrumgrossisten invoice', () {
    final d = const InvoiceParser(ownName: 'TWINS').parse(_ocr(_centrum));

    test('date equal to the due date is still found', () {
      expect(d.date.value, '2026-10-30');
      expect(d.dueDate.value, '2026-10-30');
    });

    test('amounts and certain fields', () {
      expect(d.total.value, Money.kr(521));
      expect(d.vatTotal.value, const Money(2947));
      expect(d.vatTotal.confidence, Confidence.high);
      expect(d.invoiceNumber.value, '138956');
      expect(d.invoiceNumber.confidence, Confidence.high);
      expect(d.bankgiro.value, '439-9093');
    });

    test('misread BETALD stamp and Kontant suggest paid, kind stays faktura', () {
      expect(d.payment!.kind, PaymentKind.faktura);
      expect(d.payment!.paid, isTrue);
      expect(d.payment!.confidence, Confidence.medium);
      expect(d.paidDate, '2026-10-30');
    });

    test('a known supplier is found despite the split name', () {
      final known = const InvoiceParser(knownSuppliers: ['Centrumgrossisten AB']).parse(_ocr(_centrum));
      expect(known.supplier.value, 'Centrumgrossisten AB');
      expect(known.supplier.confidence, Confidence.high);
    });
  });

  group('Systembolaget kvitto', () {
    final d = const InvoiceParser().parse(_ocr(_systembolaget));

    test('total is 4311,30, not 1,30', () {
      expect(d.total.value, const Money(431130));
      expect(d.vatTotal.value, const Money(86226));
    });

    test('supplier from the address block; return date is not offered', () {
      expect(d.supplier.value, 'Systembolaget');
      expect(d.date.value, '2026-10-29');
      expect(d.dateOptions.map((o) => o.date), isNot(contains('2026-11-28')));
      expect(d.payment!.kind, PaymentKind.kvitto);
    });

    test('a total smaller than the VAT is never used', () {
      final x = const InvoiceParser().parse(_ocr('Kvitto\nTotal 1,30\nMoms 25% 862,26'));
      expect(x.total.value, isNull);
    });
  });

  group('Z-report as read by the phone', () {
    const cats = [
      Category(id: 1, name: 'Mat', vat: VatRate.twelve),
      Category(id: 2, name: 'Tobak', vat: VatRate.twentyFive),
      Category(id: 3, name: 'Sprit', vat: VatRate.twentyFive),
      Category(id: 4, name: 'Vin', vat: VatRate.twentyFive),
      Category(id: 5, name: 'Öl', vat: VatRate.twentyFive),
    ];
    final d = const ZReportParser(cats).parse(_ocr(_zReport));

    test('Från date, print date gone, Z number', () {
      expect(d.date.value, '2026-10-30');
      expect(d.otherDates, isNot(contains('2026-10-31')));
      expect(d.zNumber.value, 'Z1-180');
      expect(d.total.value, Money.kr(12955));
    });

    test('all eight rows add up to the total', () {
      expect(d.lines.length, 8);
      expect(Money.sum(d.lines.map((l) => l.amount)), Money.kr(12955));
    });

    test('without Från the date on the title row is used', () {
      final x = const ZReportParser(cats)
          .parse(_ocr('2026-10-31 13:20\nZ-Rapport: Alla kassor 2026-10-30 23:59\nPeriodens försäljning 100,00 kr'));
      expect(x.date.value, '2026-10-30');
    });
  });

  test('differences under 1 kr give no warning', () {
    const e = AccountingValidationEngine();
    expect(e.reconcileZReport([const Money(10050)], Money.kr(100)).status, ValidationStatus.ok);
    expect(e.reconcileZReport([const Money(10100)], Money.kr(100)).status, ValidationStatus.warning);
    expect(e.checkVatLine(const InvoiceVatLine(rate: VatRate.six, vat: Money(3105), net: Money(51795))), isNull);
    expect(e.checkInvoiceArithmetic(const Money(10000), const Money(2500), const Money(12580)).status, ValidationStatus.ok);
  });

  group('Onlineförsäljning', () {
    test('Foodora paper: payment date, paid amount, document number', () {
      final d = const OnlineParser().parse(_ocr(_foodora));
      expect(d.date.value, '2026-10-09');
      expect(d.amount.value, const Money(200114));
      expect(d.documentNumber.value, '634007945393');
      expect(d.partner.value, 'Foodora');
      expect(OnlineParser.looksLikeOnline(_foodora), isTrue);
      expect(OnlineParser.looksLikeOnline(_centrum), isFalse);
    });

    test('month and year totals add it to sales, not to VAT', () {
      final online = [
        OnlineSale(paymentDate: '2026-10-09', partner: 'Foodora', amount: const Money(200114), meta: const RecordMeta(source: RecordSource.ocr)),
        OnlineSale(paymentDate: '2026-11-02', partner: 'Foodora', amount: Money.kr(100), meta: const RecordMeta(source: RecordSource.ocr)),
      ];
      final sales = [
        DailySales(
          businessDate: '2026-10-30',
          reportedTotal: Money.kr(1060),
          items: [SalesItem(categoryName: 'Mat', vat: VatRate.six, amount: Money.kr(1060))],
          meta: const RecordMeta(source: RecordSource.ocr),
        ),
      ];
      final m = const ReportGenerator()
          .monthly(year: 2026, month: 10, categories: const [], sales: sales, invoices: const [], online: online);
      expect(m.totalSales, Money.kr(1060));
      expect(m.totalOnline, const Money(200114));
      expect(m.onlineCount, 1);
      expect(m.totalAllSales, const Money(306114));
      expect(m.totalOutputVat, Money.kr(60));
      final y = const ReportGenerator().yearly(year: 2026, sales: sales, invoices: const [], online: online);
      expect(y.rows[9].sales, const Money(306114));
      expect(y.rows[9].online, const Money(200114));
      expect(y.online, const Money(210114));
    });

    test('stored, duplicate warning and deletion', () async {
      sqfliteFfiInit();
      final repo = Repository(await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
      final sale = OnlineSale(
          paymentDate: '2026-10-09',
          partner: 'Foodora',
          documentNumber: '634007945393',
          amount: const Money(200114),
          meta: const RecordMeta(source: RecordSource.ocr));
      final id = await repo.saveOnlineSale(sale);
      expect((await repo.onlineSalesBetween('2026-10-01', '2026-10-31')).single.amount, const Money(200114));
      expect((await repo.findDuplicateOnlineSales(sale)).length, 1);
      expect(await repo.knownPartners(), ['Foodora']);
      final recent = await repo.recentRegistrations();
      expect(recent.single.typeLabel, 'Onlineförsäljning');
      await repo.deleteOnlineSale(id);
      expect(await repo.onlineSalesBetween('2026-10-01', '2026-10-31'), isEmpty);
      await repo.db.close();
    });
  });
}
