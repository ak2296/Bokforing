import 'package:bokforing/data/database.dart';
import 'package:bokforing/data/repository.dart';
import 'package:bokforing/domain/balances.dart';
import 'package:bokforing/domain/bank_matcher.dart';
import 'package:bokforing/domain/bank_statement.dart';
import 'package:bokforing/domain/cost_types.dart';
import 'package:bokforing/domain/ledger.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/pay_method.dart';
import 'package:bokforing/domain/payment_detector.dart';
import 'package:bokforing/export/sie_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _meta = RecordMeta(source: RecordSource.manual);

Invoice _receipt(PayMethod m, {String supplier = 'Grossisten AB', int total = 125000, String date = '2026-11-13', bool paid = true}) =>
    Invoice(
      invoiceDate: date,
      supplier: supplier,
      total: Money(total),
      vatTotal: Money(total ~/ 5),
      costType: CostType.goods.key,
      paid: paid,
      paidDate: paid ? date : null,
      payMethod: m,
      meta: _meta,
    );

List<SieVoucher> _book(List<Invoice> invoices, {CompanyForm? form}) =>
    SieExport.vouchers(fromIso: '2026-11-01', toIso: '2026-11-30', sales: const [], invoices: invoices, form: form);

void main() {
  group('Accounts', () {
    test('bank is 1930, cash 1910, and a private payment follows the company form', () {
      expect(PayMethod.bank.account(null), 1930);
      expect(PayMethod.cash.account(CompanyForm.aktiebolag), 1910);
      expect(PayMethod.owner.account(CompanyForm.enskildFirma), 2018);
      expect(PayMethod.owner.account(CompanyForm.aktiebolag), 2893);
      expect(PayMethod.parse('cash'), PayMethod.cash);
      expect(PayMethod.parse('nonsense'), PayMethod.bank);
      expect(PayMethod.parse(null), PayMethod.bank);
    });

    test('the same receipt is booked from the account of how it was paid', () {
      int creditAccount(PayMethod m, {CompanyForm? form}) {
        final v = _book([_receipt(m)], form: form).single;
        expect(v.rows.fold<int>(0, (n, r) => n + r.amount.ore), 0, reason: 'balanced');
        return v.rows.firstWhere((r) => r.amount.isNegative).account;
      }

      expect(creditAccount(PayMethod.bank), 1930);
      expect(creditAccount(PayMethod.cash), 1910);
      expect(creditAccount(PayMethod.owner, form: CompanyForm.aktiebolag), 2893);
      expect(creditAccount(PayMethod.owner, form: CompanyForm.enskildFirma), 2018);
    });

    test('an invoice paid later is paid from the chosen account, the debt is cleared', () {
      final inv = Invoice(
        invoiceDate: '2026-11-03',
        dueDate: '2026-11-10',
        supplier: 'Grossisten AB',
        total: const Money(125000),
        vatTotal: const Money(25000),
        costType: CostType.goods.key,
        paid: true,
        paidDate: '2026-11-12',
        payMethod: PayMethod.cash,
        meta: _meta,
      );
      final v = _book([inv]);
      expect(v.length, 2);
      expect(v[0].rows.last.account, 2440);
      expect(v[1].rows.map((r) => r.account), [2440, 1910]);
    });
  });

  group('Balance sheet', () {
    test('an enskild firma owner deposit counts in equity and the sheet balances', () {
      final vouchers = _book([_receipt(PayMethod.owner, total: 60000)], form: CompanyForm.enskildFirma);
      final opening = OpeningBalances('2026-11-01', [
        BalanceEntry(id: '1', kind: BalanceKind.bank, name: 'Företagskonto', amount: Money.kr(10000)),
      ]);
      final sheet = BalanceSheet.build(opening, Ledger.of(vouchers), '2026-11-30');
      expect(sheet.balances, isTrue, reason: '${sheet.totalAssets} vs ${sheet.totalEquityDebts}');
      final deposit = sheet.equityDebtRows.firstWhere((r) => r.label == 'Egna insättningar');
      expect(deposit.amount, const Money(60000));
    });

    test('an aktiebolag owner payment is a debt to the owner and the sheet balances', () {
      final vouchers = _book([_receipt(PayMethod.owner, total: 60000)], form: CompanyForm.aktiebolag);
      final opening = OpeningBalances('2026-11-01', [
        BalanceEntry(id: '1', kind: BalanceKind.bank, name: 'Företagskonto', amount: Money.kr(10000)),
      ]);
      final sheet = BalanceSheet.build(opening, Ledger.of(vouchers), '2026-11-30');
      expect(sheet.balances, isTrue);
      expect(sheet.equityDebtRows.firstWhere((r) => r.label == 'Övriga skulder').amount, const Money(60000));
    });
  });

  group('Reading a paper', () {
    test('cash and change suggest Kontant, a card slip suggests Bank / kort', () {
      const detector = PaymentDetector();
      final cash = detector.detect(['KVITTO', 'Bageri Syd', 'Summa 380,00', 'Kontant 400,00', 'Växel 20,00', '14:32']);
      expect(cash.method, PayMethod.cash);
      expect(cash.methodReason, contains('växel'));
      final card = detector.detect(['KVITTO', 'Clas Ohlson', 'Summa 599,00', 'Kortnr **** 1234', 'Godkänd', '12:01']);
      expect(card.method, PayMethod.bank);
      final none = detector.detect(['Faktura', 'Förfallodatum 2026-11-30', 'Bankgiro 123-4567']);
      expect(none.method, isNull);
    });
  });

  group('Bank file', () {
    BankRow row(String date, int ore, String text) => BankRow(date: date, text: text, amount: Money(-ore));

    test('two unpaid invoices with the same amount are not sure', () {
      final r = BankMatcher.match([row('2026-11-18', 120000, 'BAGERI SYD')],
          [_receipt(PayMethod.bank, supplier: 'Bageri Syd', total: 120000, paid: false), _receipt(PayMethod.bank, supplier: 'Bageri Norr', total: 120000, paid: false)]);
      expect(r.matches.single.sure, isFalse);
      expect(r.matches.single.note, contains('samma belopp'));
    });

    test('a payment that also fits a receipt paid by card is marked for checking', () {
      final paid = _receipt(PayMethod.bank, supplier: 'El AB', total: 105000, date: '2026-11-17');
      final unpaid = _receipt(PayMethod.bank, supplier: 'El AB', total: 105000, date: '2026-11-09', paid: false);
      final r = BankMatcher.match([row('2026-11-18', 105000, 'EL AB')], [unpaid], paidByBank: [paid]);
      expect(r.matches.single.sure, isFalse);
      expect(r.matches.single.note, contains('redan är betalt med kort'));
    });

    test('a payment of a receipt registered as Bank / kort is explained, not missing; cash and private are not searched', () {
      final bank = _receipt(PayMethod.bank, supplier: 'Grossisten AB', total: 125000);
      final cash = _receipt(PayMethod.cash, supplier: 'Bageri', total: 38000);
      final r = BankMatcher.match(
        [row('2026-11-14', 125000, 'GROSSISTEN AB'), row('2026-11-15', 38000, 'KONTANTUTTAG'), row('2026-11-16', 9900, 'OKÄNT')],
        const [],
        paidByBank: [bank].where((i) => i.payMethod == PayMethod.bank).toList(),
      );
      expect(r.explained.length, 1);
      expect(r.explained.single.$2.supplier, 'Grossisten AB');
      expect(r.unmatchedOut.map((x) => x.text), ['KONTANTUTTAG', 'OKÄNT']);
      // a cash receipt is never offered as a reason for a bank payment
      final withCash = BankMatcher.match([row('2026-11-15', 38000, 'X')], const [], paidByBank: [cash]);
      expect(withCash.explained, isEmpty);
    });
  });

  group('On the phone', () {
    late Repository repo;
    setUp(() async {
      sqfliteFfiInit();
      repo = Repository(await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
    });
    tearDown(() => repo.db.close());

    test('how it was paid is saved and read back; an old record reads as Bank / kort', () async {
      final id = await repo.saveInvoice(_receipt(PayMethod.cash));
      expect((await repo.invoicesBetween('2026-11-01', '2026-11-30')).single.payMethod, PayMethod.cash);
      // a row from before the field existed has the default
      await repo.db.update('invoices', {'pay_method': 'bank'}, where: 'id = ?', whereArgs: [id]);
      expect((await repo.invoicesBetween('2026-11-01', '2026-11-30')).single.payMethod, PayMethod.bank);
    });

    test('marking paid stores the method, marking unpaid again resets it', () async {
      final id = await repo.saveInvoice(_receipt(PayMethod.bank, paid: false));
      await repo.setInvoicePaid(id, paid: true, paidDate: '2026-11-20', payMethod: PayMethod.owner);
      var inv = (await repo.invoicesBetween('2026-11-01', '2026-11-30')).single;
      expect((inv.paid, inv.payMethod), (true, PayMethod.owner));
      await repo.setInvoicePaid(id, paid: false);
      inv = (await repo.invoicesBetween('2026-11-01', '2026-11-30')).single;
      expect((inv.paid, inv.payMethod), (false, PayMethod.bank));
    });
  });
}
