import 'package:bokforing/data/database.dart';
import 'package:bokforing/data/repository.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/online_parser.dart';
import 'package:bokforing/domain/payment_detector.dart';
import 'package:bokforing/domain/reports.dart';
import 'package:bokforing/domain/text_patterns.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The owner's Foodora paper, as the phone read it.
const _foodora = '''
Snabbgross
Följesod-.
Foodora AB Stockholm
Fleminggatan 20
112 26 Stockholm   foodora
FAKTURA
Fakturanummer:   7002885471   Ankan restaurang & pizzeria
Kundnummer:   ENQN   Provvägen 12A
Org. Nr.:   1212121212   123 45 Malmö
Moms Nr:   SE121212121201
Datum:   31-10-2026
Förfallodatum:   07-11-2026
Självfaktura 7002885471-1 för perioden 23.10.2026 -31.10.2026
Beskrivning   Antal   Bruttobelopp   Nettobelopp
8 tkörningsorders   13   2.277.00 SEK   2,148.12 SEK
JAvhämtningsorders   3   617.01 SEK   582.08 SEK
Rabattsammanställning   Antal   Underlag för rabatt   Rabatt %   Rabattbelopp
Rabatt enligt avtal 30.00%   13   -2.277.00 SEK   30.00   -683.10 SEK
Rabatt avhämtningsorders 30.00%   3   -617.00 SEK   30.00   -185.10 SEK
Era försäljningar exkl. moms   1,862.00 SEK
Moms 6%   111.72 SEK
Totalt (1)   1,973.72 SEK
Faktura 7002885471-2 för perioden 23.10.2026 -31.10.2026
Beskrivning   Antal   Totalt Netto
Oktober Uppkoppling och administrationsavgift   -100.00 SEK
Förpackningar   1   -2,556.00 SEK
Kampanj   2   -17.92 SEK
Foodoras försäljningar exkl. moms
-2,673.92 SEK
Er ingående moms 25% (-2673.92)   -668.48 SEK
Totalt (2)   -3,342.40 SEK
Öresavrundning   0.00 SEK
Att betala (1) + (2)   -1,368.68 SEK
Postadress   Kontaktinformation   Bankgiro   Betalningsmottagare
Foodora AB Stockholm   Hemsida www.foodora.se   5462-0000   Foodora AB Stockholm''';

void main() {
  group('Foodora: your sales and their fees on one paper', () {
    final d = const OnlineParser().parse(OcrResult.fromPlainText(_foodora));

    test('is noticed as two parts', () {
      expect(OnlineParser.isCombined(_foodora), isTrue);
      expect(OnlineParser.isCombined('Foodora\nBetalt belopp 1 000,00'), isFalse);
    });

    test('part 1: your sales with 6 % output moms', () {
      expect(d.partner.value, 'Foodora');
      expect(d.amount.value, const Money(197372));
      expect(d.amount.confidence, Confidence.high);
      expect(d.vat.value, const Money(11172));
      expect(d.vatRate, VatRate.six);
      expect(d.date.value, '2026-10-31');
    });

    test('part 2: their fees as an invoice with 25 % input moms', () {
      final f = d.feesInvoice!;
      expect(f.total.value, const Money(334240));
      expect(f.total.confidence, Confidence.high);
      expect(f.vatTotal.value, const Money(66848));
      expect(f.vatLines.single.rate, VatRate.twentyFive);
      expect(f.net, const Money(267392));
      expect(f.date.value, '2026-10-31');
      expect(f.dueDate.value, '2026-11-07');
      expect(f.invoiceNumber.value, '7002885471-2');
      expect(f.supplier.value, 'Foodora AB Stockholm');
      expect(f.payment!.kind, PaymentKind.faktura);
      expect(f.notes.join(), contains('368,68'));
    });

    test('sales minus fees is the bottom line of the paper', () {
      expect(d.amount.value! - d.feesInvoice!.total.value!, const Money(-136868));
    });
  });

  test('a plain payout paper keeps working without moms', () {
    final d = const OnlineParser().parse(
        OcrResult.fromPlainText('Foodora\nBetalningsbekräftelse\nBetalningsdatum 2026-10-09\nBetalt belopp 2 001,14'));
    expect(d.amount.value, const Money(200114));
    expect(d.vat.hasValue, isFalse);
    expect(d.feesInvoice, isNull);
  });

  test('online moms is output moms in the reports', () {
    final sale = OnlineSale(
      paymentDate: '2026-10-31',
      partner: 'Foodora',
      amount: const Money(197372),
      vat: const Money(11172),
      vatRate: VatRate.six,
      meta: const RecordMeta(source: RecordSource.ocr),
    );
    final payout = OnlineSale(
        paymentDate: '2026-10-09', partner: 'Foodora', amount: Money.kr(100), meta: const RecordMeta(source: RecordSource.ocr));
    final year = const ReportGenerator().yearly(year: 2026, sales: const [], invoices: const [], online: [sale, payout]);
    expect(year.rows[9].outputVat, const Money(11172));
    expect(year.rows[9].online, const Money(207372));
    final month = const ReportGenerator()
        .monthly(year: 2026, month: 10, categories: const [], sales: const [], invoices: const [], online: [sale, payout]);
    expect(month.totalOutputVat, const Money(11172));
    expect(month.onlineVat, const Money(11172));
  });

  test('online moms is stored and read back', () async {
    sqfliteFfiInit();
    final repo = Repository(await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
    final id = await repo.saveOnlineSale(OnlineSale(
      paymentDate: '2026-10-31',
      partner: 'Foodora',
      amount: const Money(197372),
      vat: const Money(11172),
      vatRate: VatRate.six,
      meta: const RecordMeta(source: RecordSource.ocr),
    ));
    final back = (await repo.onlineSale(id))!;
    expect(back.vat, const Money(11172));
    expect(back.vatRate, VatRate.six);
    final plainId = await repo.saveOnlineSale(OnlineSale(
        paymentDate: '2026-10-09', partner: 'Foodora', amount: Money.kr(100), meta: const RecordMeta(source: RecordSource.ocr)));
    final plain = (await repo.onlineSale(plainId))!;
    expect(plain.vat, Money.zero);
    expect(plain.vatRate, isNull);
    await repo.db.close();
  });
}
