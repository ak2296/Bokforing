import 'package:bokforing/domain/bank_match.dart';
import 'package:bokforing/domain/bank_statement.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:flutter_test/flutter_test.dart';

const _meta = RecordMeta(source: RecordSource.manual);

DailySales _day(String date, int card) => DailySales(
      businessDate: date,
      reportedTotal: Money.kr(card),
      items: [SalesItem(categoryName: 'Mat', vat: VatRate.twelve, amount: Money.kr(card))],
      card: Money.kr(card),
      cash: Money.zero,
      meta: _meta,
    );

BankRow _bank(String date, num kr) => BankRow(date: date, text: 'x', amount: Money((kr * 100).round()));

void main() {
  final today = DateTime(2026, 11, 30);

  test('one deposit pays several days of card takings minus a fee', () {
    final lines = ZBankMatcher.matchZ(
      [_day('2026-11-08', 8000), _day('2026-11-09', 8000), _day('2026-11-10', 8310)],
      [_bank('2026-11-12', 23_800)],
      today: today,
    );
    expect(lines.length, 1);
    expect(lines.single.matched, isTrue);
    expect(lines.single.days, ['2026-11-08', '2026-11-09', '2026-11-10']);
    expect(lines.single.fee, Money.kr(510));
  });

  test('a deposit above the takings, or with a fee over 6 %, is not a match', () {
    expect(ZBankMatcher.matchZ([_day('2026-11-08', 1000)], [_bank('2026-11-10', 1001)], today: today).single.matched, isFalse);
    expect(ZBankMatcher.matchZ([_day('2026-11-08', 1000)], [_bank('2026-11-10', 900)], today: today).single.matched, isFalse);
  });

  test('days without a deposit are listed, and recent ones are only waiting', () {
    final lines = ZBankMatcher.matchZ(
      [_day('2026-11-02', 1000), _day('2026-11-28', 500)],
      [_bank('2026-11-04', 980)],
      today: today,
    );
    expect(lines.map((l) => '${l.days.join(',')} ${l.matched} ${l.pending}'), [
      '2026-11-02 true false',
      '2026-11-28 false true',
    ]);
  });

  test('days that follow each other with no deposit become one line', () {
    final lines = ZBankMatcher.matchZ([_day('2026-11-02', 100), _day('2026-11-03', 100), _day('2026-11-10', 100)], const [], today: today);
    expect(lines.map((l) => l.days), [
      ['2026-11-02', '2026-11-03'],
      ['2026-11-10'],
    ]);
    expect(lines.first.expected, Money.kr(200));
  });

  test('the oldest day paid some other way does not block the later ones', () {
    final lines = ZBankMatcher.matchZ(
      [_day('2026-11-02', 4000), _day('2026-11-03', 1000)],
      [_bank('2026-11-06', 985)],
      today: today,
    );
    expect(lines.firstWhere((l) => l.matched).days, ['2026-11-03']);
    expect(lines.firstWhere((l) => !l.matched).days, ['2026-11-02']);
  });
}
