import 'package:bokforing/domain/cash_summary.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/pay_method.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:flutter_test/flutter_test.dart';

const _meta = RecordMeta(source: RecordSource.manual);

DailySales _day(String date, {Money? card, Money? cash}) => DailySales(
      businessDate: date,
      reportedTotal: Money.kr(1000),
      items: const [SalesItem(categoryName: 'Mat', vat: VatRate.twelve, amount: Money(100000))],
      card: card,
      cash: cash,
      meta: _meta,
    );

Invoice _inv(PayMethod m, int kr) => Invoice(
      invoiceDate: '2026-11-03',
      supplier: 'X',
      total: Money.kr(kr),
      vatTotal: Money.kr(kr ~/ 5),
      costType: 'goods',
      payMethod: m,
      paid: true,
      meta: _meta,
    );

void main() {
  test('cash and card in from the Z-reports, out by how each invoice was paid', () {
    final s = CashSummary.of(
      [_day('2026-11-01', card: Money.kr(700), cash: Money.kr(300)), _day('2026-11-02', card: Money.kr(500), cash: Money.kr(200))],
      [_inv(PayMethod.cash, 120), _inv(PayMethod.bank, 400), _inv(PayMethod.owner, 50), _inv(PayMethod.cash, -20)],
    );
    expect((s.cashIn, s.cardIn), (Money.kr(500), Money.kr(1200)));
    expect((s.cashOut, s.bankOut, s.ownerOut), (Money.kr(100), Money.kr(400), Money.kr(50)));
    expect(s.cashLeft, Money.kr(400));
    expect(s.bankNet, Money.kr(800));
    expect(s.zDaysWithoutPayments, 0);
  });

  test('a Z-report without cash or card figures is counted as missing them', () {
    final s = CashSummary.of([_day('2026-11-01', card: Money.kr(100)), _day('2026-11-02')], const []);
    expect((s.zDays, s.zDaysWithPayments, s.zDaysWithoutPayments), (2, 1, 1));
    expect(s.cashLeft, Money.zero);
  });
}
