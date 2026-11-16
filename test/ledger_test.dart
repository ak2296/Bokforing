import 'package:bokforing/domain/ledger.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/export/sie_export.dart';
import 'package:bokforing/export/table_export.dart';
import 'package:flutter_test/flutter_test.dart';

List<SieVoucher> _vouchers() => [
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
    ];

void main() {
  _vatTest();
  test('the ledger sums every account and the trial balance balances', () {
    final l = Ledger.of(_vouchers());
    expect(l.accounts.map((a) => a.number), [1910, 2440, 2611, 2641, 3001, 4010]);
    expect(l.totalDebit, Money.kr(1750));
    expect(l.totalCredit, Money.kr(1750));
    expect(l.balances, isTrue);
    expect(l.income, Money.kr(1000));
    expect(l.costs, Money.kr(400));
    expect(l.result, Money.kr(600));
  });

  test('the report tables carry every verification and the totals', () {
    final l = Ledger.of(_vouchers());
    final list = voucherListTable(l, 'november 2026');
    expect(list.rows.length, 6);
    expect(list.rows.first.first, 'A1');
    expect(list.totals!.last, '1750,00');
    final book = generalLedgerTable(l, 'november 2026');
    expect(book.rows.first.first, 'Konto 1910 Kassa');
    final trial = trialBalanceTable(l, 'november 2026');
    expect(trial.rows.length, 6);
    expect(trial.totals![1], 'Debet och kredit stämmer');
    final result = incomeStatementTable(l, 'november 2026');
    expect(result.totals!.last, '600,00');
  });
}

void _vatTest() {
  test('the momsunderlag puts sales, output VAT and input VAT in Skatteverket boxes', () {
    final l = Ledger.of([
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
    final t = vatBasisTable(l, 'november 2026');
    expect(t.rows[0], ['05', 'Momspliktig försäljning (underlag, utan moms)', '1000,00', '0,00', '0,00', '1000,00']);
    expect(t.rows[1][2], '250,00');
    expect(t.rows[3][5], '100,00');
    expect(t.totals![0], '49');
    expect(t.totals![5], '150,00');
  });
}
