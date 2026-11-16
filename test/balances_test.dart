import 'package:bokforing/domain/balances.dart';
import 'package:bokforing/domain/ledger.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/export/sie_export.dart';
import 'package:bokforing/export/table_export.dart';
import 'package:flutter_test/flutter_test.dart';

OpeningBalances _opening() => OpeningBalances('2026-01-01', [
      BalanceEntry(id: '1', kind: BalanceKind.bank, name: 'Företagskonto', amount: Money.kr(84300)),
      BalanceEntry(id: '2', kind: BalanceKind.asset, name: 'Kaffemaskin', amount: Money.kr(32000), years: 5),
      BalanceEntry(id: '3', kind: BalanceKind.loan, name: 'Banklån', amount: Money.kr(60000), monthsLeft: 36, ratePercent: 5.4),
    ]);

void main() {
  test('equity is assets minus debts, and the entries survive a save and load', () {
    final o = _opening();
    expect(o.assets, Money.kr(116300));
    expect(o.debts, Money.kr(60000));
    expect(o.equity, Money.kr(56300));
    final back = OpeningBalances.decode(o.encode(), fallbackDate: '2000-01-01');
    expect(back.date, '2026-01-01');
    expect(back.entries.length, 3);
    expect(back.entries[2].ratePercent, 5.4);
    expect(back.equity, o.equity);
    expect(OpeningBalances.decode(null, fallbackDate: '2026-01-01').isEmpty, isTrue);
    expect(OpeningBalances.decode('not json', fallbackDate: '2026-01-01').isEmpty, isTrue);
  });

  test('the balance sheet balances with the opening balances and the verifications', () {
    final ledger = Ledger.of([
      SieVoucher('A', 1, '2026-11-01', 'Dagskassa', [
        SieRow(1910, 'Kassa', Money.kr(1250)),
        SieRow(3001, 'Försäljning 25 %', Money.kr(-1000)),
        SieRow(2611, 'Utgående moms 25 %', Money.kr(-250)),
      ]),
      SieVoucher('C', 1, '2026-11-02', 'Grossisten', [
        SieRow(4010, 'Varuinköp', Money.kr(400)),
        SieRow(2641, 'Ingående moms', Money.kr(100)),
        SieRow(2440, 'Leverantörsskulder', Money.kr(-500)),
      ]),
    ]);
    final s = BalanceSheet.build(_opening(), ledger, '2026-11-30');
    // 116 300 + cash 1 250; the input VAT is set against the moms debt
    expect(s.totalAssets, Money.kr(117550));
    expect(s.balances, isTrue);
    final table = balanceSheetTable(s);
    expect(table.rows.first.first, 'TILLGÅNGAR');
    expect(table.totals!.last, '117550,00');
  });

  test('depreciation runs straight to zero and a loan has a first month', () {
    final o = _opening();
    final plan = depreciationPlan(o.entries[1], 2026);
    expect(plan.length, 5);
    expect(plan.first.amount, Money.kr(6400));
    expect(plan.last.valueAtEnd, Money.zero);
    final loan = loanFirstMonth(o.entries[2])!;
    expect(loan.amortisation, Money(166666));
    expect(loan.interest, Money(27000));
    expect(depreciationPlan(o.entries[0], 2026), isEmpty);
  });
}
