import 'package:bokforing/data/database.dart';
import 'package:bokforing/data/repository.dart';
import 'package:bokforing/domain/bank_matcher.dart';
import 'package:bokforing/domain/bank_statement.dart';
import 'package:bokforing/domain/cash_summary.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/pay_method.dart';
import 'package:bokforing/export/sie_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _meta = RecordMeta(source: RecordSource.manual);

/// A receipt of 1 250 kr paid 500 in cash and 750 by card.
Invoice _split({bool paid = true, String paidDate = '2026-11-13', String date = '2026-11-13'}) => Invoice(
      invoiceDate: date,
      supplier: 'Grossisten AB',
      total: Money.kr(1250),
      vatTotal: Money.kr(250),
      costType: 'goods',
      paid: paid,
      paidDate: paid ? paidDate : null,
      payMethod: PayMethod.bank,
      paymentSplit: [PaymentPart(PayMethod.cash, Money.kr(500)), PaymentPart(PayMethod.bank, Money.kr(750))],
      meta: _meta,
    );

void main() {
  test('a split is valid only with two or more parts that are not zero and add up', () {
    final total = Money.kr(1250);
    expect(PaymentPart.valid([PaymentPart(PayMethod.cash, Money.kr(500)), PaymentPart(PayMethod.bank, Money.kr(750))], total), isTrue);
    expect(PaymentPart.valid([PaymentPart(PayMethod.cash, Money.kr(500)), PaymentPart(PayMethod.bank, Money.kr(700))], total), isFalse);
    expect(PaymentPart.valid([PaymentPart(PayMethod.cash, Money.zero), PaymentPart(PayMethod.bank, total)], total), isFalse);
    expect(PaymentPart.valid([PaymentPart(PayMethod.bank, total)], total), isFalse);
    // A credit note splits with minus signs.
    expect(PaymentPart.valid([PaymentPart(PayMethod.cash, Money.kr(-100)), PaymentPart(PayMethod.bank, Money.kr(-150))], Money.kr(-250)), isTrue);
  });

  test('the parts are written and read back; unreadable text means not split', () {
    final parts = _split().paymentSplit;
    final back = PaymentPart.decode(PaymentPart.encode(parts));
    expect(back.map((p) => (p.method, p.amount)), parts.map((p) => (p.method, p.amount)));
    expect(PaymentPart.decode(null), isEmpty);
    expect(PaymentPart.decode('nonsense'), isEmpty);
  });

  test('an invoice without a split has one part: the whole amount with its method', () {
    final inv = Invoice(
        invoiceDate: '2026-11-13', supplier: 'X', total: Money.kr(100), vatTotal: Money.kr(20), costType: 'goods', payMethod: PayMethod.cash, meta: _meta);
    expect(inv.parts.single.method, PayMethod.cash);
    expect(inv.payLabel, 'Kontant');
    expect(_split().payLabel, 'Kontant 500,00 + Bank / kort 750,00'.replaceAll(',00', ''));
    expect(_split().bankPart, Money.kr(750));
  });

  test('the books take each part from its own account', () {
    final v = SieExport.vouchers(fromIso: '2026-11-01', toIso: '2026-11-30', sales: const [], invoices: [_split()]).single;
    final credits = {for (final r in v.rows) if (r.credit > Money.zero) r.account: r.credit};
    expect(credits, {1910: Money.kr(500), 1930: Money.kr(750)});
    expect(v.balances, isTrue);
  });

  test('an invoice paid later: the payment voucher credits each part', () {
    final vouchers = SieExport.vouchers(
        fromIso: '2026-11-01', toIso: '2026-11-30', sales: const [], invoices: [_split(date: '2026-11-03', paidDate: '2026-11-20')]);
    final pay = vouchers.firstWhere((v) => v.text.startsWith('Betalning'));
    expect({for (final r in pay.rows) if (r.credit > Money.zero) r.account: r.credit}, {1910: Money.kr(500), 1930: Money.kr(750)});
    expect(pay.balances, isTrue);
  });

  test('cash and bank out count each part', () {
    final s = CashSummary.of(const [], [_split()]);
    expect((s.cashOut, s.bankOut), (Money.kr(500), Money.kr(750)));
  });

  test('only the bank part is looked for in the bank file', () {
    final row = BankRow(date: '2026-11-13', text: 'Kortköp', amount: Money.kr(-750));
    final res = BankMatcher.match([row], const [], paidByBank: [_split().copyWith(id: 1)]);
    expect(res.explained.length, 1);
    final whole = BankRow(date: '2026-11-13', text: 'Kortköp', amount: Money.kr(-1250));
    expect(BankMatcher.match([whole], const [], paidByBank: [_split().copyWith(id: 1)]).explained, isEmpty);
  });

  group('On the phone', () {
    late Repository repo;
    setUp(() async {
      sqfliteFfiInit();
      repo = Repository(await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
    });
    tearDown(() => repo.db.close());

    test('the split is saved and read back; marking an invoice unpaid clears it', () async {
      final id = await repo.saveInvoice(_split());
      var back = (await repo.invoicesBetween('2026-11-01', '2026-11-30')).single;
      expect(back.paymentSplit.map((p) => (p.method, p.amount)), [(PayMethod.cash, Money.kr(500)), (PayMethod.bank, Money.kr(750))]);
      await repo.setInvoicePaid(id, paid: false);
      back = (await repo.invoicesBetween('2026-11-01', '2026-11-30')).single;
      expect(back.paymentSplit, isEmpty);
    });

    test('"Markera som betald" can store a split', () async {
      final id = await repo.saveInvoice(_split(paid: false));
      await repo.setInvoicePaid(id,
          paid: true,
          paidDate: '2026-11-20',
          payMethod: PayMethod.bank,
          split: [PaymentPart(PayMethod.cash, Money.kr(250)), PaymentPart(PayMethod.bank, Money.kr(1000))]);
      final back = (await repo.invoicesBetween('2026-11-01', '2026-11-30')).single;
      expect(back.parts.map((p) => p.amount), [Money.kr(250), Money.kr(1000)]);
    });
  });
}
