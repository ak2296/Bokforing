import 'package:bokforing/data/database.dart';
import 'package:bokforing/data/repository.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/text_patterns.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:bokforing/domain/z_report_parser.dart';
import 'package:bokforing/export/cash_report.dart';
import 'package:bokforing/export/sie_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _cats = [
  Category(id: 1, name: 'Mat', vat: VatRate.twelve),
  Category(id: 2, name: 'Dryck', vat: VatRate.twentyFive),
];
const _meta = RecordMeta(source: RecordSource.manual);

ZReportDraft _read(String text) => const ZReportParser(_cats).parse(OcrResult.fromPlainText(text));

DailySales _day({Money? card, Money? cash, Money? cashLeft, String date = '2026-11-14'}) => DailySales(
      businessDate: date,
      zNumber: '126',
      reportedTotal: Money.kr(6180),
      items: const [
        SalesItem(categoryName: 'Mat', vat: VatRate.twelve, amount: Money(448000)),
        SalesItem(categoryName: 'Dryck', vat: VatRate.twentyFive, amount: Money(170000)),
      ],
      card: card,
      cash: cash,
      cashLeft: cashLeft,
      meta: _meta,
    );

void main() {
  group('Reading the payments and the till', () {
    test('card, cash, cash in and out and the cash left are read when the report names them', () {
      final d = _read('Z-rapport\nFörsäljning per varugrupp\nMat 4 480,00\nDryck 1 700,00\nTotal försäljning 6 180,00\n'
          'Betalning\nKortbetalningar 4 600,00\nKontanter 1 580,00\nInsättning i kassan 0,00\nUttag ur kassan 300,00\nKassabehållning 2 340,00');
      expect(d.cash.card.value, Money.kr(4600));
      expect(d.cash.cash.value, Money.kr(1580));
      expect(d.cash.cashIn.value, Money.zero);
      expect(d.cash.cashOut.value, Money.kr(300));
      expect(d.cash.cashLeft.value, Money.kr(2340));
    });

    test('card and cash that add up to the day are sure; Swish counts with the card', () {
      final d = _read('Z-rapport\nFörsäljning per varugrupp\nMat 4 480,00\nDryck 1 700,00\nTotal försäljning 6 180,00\n'
          'Kort 3 600,00\nSwish 1 000,00\nKontant 1 580,00');
      expect(d.cash.card.value, Money.kr(4600));
      expect(d.cash.card.confidence, Confidence.high);
      expect(d.cash.cash.confidence, Confidence.high);
    });

    test('card and cash that do not add up are only medium sure', () {
      final d = _read('Z-rapport\nFörsäljning per varugrupp\nMat 4 480,00\nDryck 1 700,00\nTotal försäljning 6 180,00\nKort 4 000,00\nKontant 1 580,00');
      expect(d.cash.card.confidence, Confidence.medium);
    });

    test('other words for the same figures: utgående kassa, kassasaldo, utbetalningar, kontanter ut, closing cash', () {
      expect(_read('Z-rapport\nUtgående kassa 1 000,00').cash.cashLeft.value, Money.kr(1000));
      expect(_read('Z-rapport\nKassasaldo 2 000,00').cash.cashLeft.value, Money.kr(2000));
      expect(_read('Z-rapport\nUtbetalningar 150,00').cash.cashOut.value, Money.kr(150));
      expect(_read('Z-rapport\nKontanter ut 75,50').cash.cashOut.value, const Money(7550));
      expect(_read('Z-rapport\nClosing cash 3 000,00').cash.cashLeft.value, Money.kr(3000));
    });

    test('a label with its amount on the next line is read', () {
      final d = _read('Z-rapport\nKassabehållning\n2 340,00');
      expect(d.cash.cashLeft.value, Money.kr(2340));
    });

    test('a report without these lines gives nothing, and cash in is not mistaken for cash', () {
      final d = _read('Z-rapport\nFörsäljning per varugrupp\nMat 4 480,00\nTotal försäljning 4 480,00');
      expect(d.cash.isEmpty, isTrue);
      final e = _read('Z-rapport\nKontanter ut 75,00');
      expect(e.cash.cash.hasValue, isFalse);
      expect(e.cash.cashOut.value, Money.kr(75));
    });
  });

  group('Books and reports', () {
    List<SieVoucher> book(List<DailySales> days) =>
        SieExport.vouchers(fromIso: '2026-11-01', toIso: '2026-11-30', sales: days, invoices: const []);

    test('a saved split puts the card share on the bank and the rest on Kassa; the verification balances', () {
      final v = book([_day(card: Money.kr(4600), cash: Money.kr(1580))]).single;
      final debits = {for (final r in v.rows.where((r) => !r.amount.isNegative)) r.account: r.amount};
      expect(debits[1930], Money.kr(4600));
      expect(debits[1910], Money.kr(1580));
      expect(v.rows.fold<int>(0, (n, r) => n + r.amount.ore), 0);
    });

    test('without a saved split the whole day goes to Kassa as before', () {
      final v = book([_day()]).single;
      expect(v.rows.where((r) => r.account == 1910 && !r.amount.isNegative).single.amount, Money.kr(6180));
      expect(v.rows.any((r) => r.account == 1930), isFalse);
    });

    test('the Kassarapport lists only days with figures and ends with the last cash left', () {
      final t = cashReportTable([
        _day(card: Money.kr(4600), cash: Money.kr(1580), cashLeft: Money.kr(2340)),
        _day(date: '2026-11-13', card: Money.kr(5020), cash: Money.kr(2100), cashLeft: Money.kr(1060)),
        _day(date: '2026-11-12'),
      ], 'november 2026');
      expect(t.rows.length, 2);
      expect(t.rows.first.first, '2026-11-13');
      expect(t.totals!.last.replaceAll(RegExp(r'\s'), ''), '2340,00');
    });
  });

  group('On the phone', () {
    late Repository repo;
    setUp(() async {
      sqfliteFfiInit();
      repo = Repository(await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
    });
    tearDown(() => repo.db.close());

    test('the figures are saved and read back; a day without them stays empty', () async {
      await repo.saveDailySales(_day(card: Money.kr(4600), cash: Money.kr(1580), cashLeft: Money.kr(2340)));
      await repo.saveDailySales(_day(date: '2026-11-15'));
      final days = await repo.dailySalesBetween('2026-11-01', '2026-11-30');
      final a = days.firstWhere((d) => d.businessDate == '2026-11-14');
      final b = days.firstWhere((d) => d.businessDate == '2026-11-15');
      expect((a.card, a.cash, a.cashLeft), (Money.kr(4600), Money.kr(1580), Money.kr(2340)));
      expect(b.hasCashData, isFalse);
    });
  });
}
