import '../export/sie_export.dart';
import 'money.dart';

/// One transaction line in an account: which verification, when, the text, and
/// the amount on the debit or credit side.
class LedgerLine {
  final String ver;
  final String date;
  final String text;
  final Money debit;
  final Money credit;
  const LedgerLine(this.ver, this.date, this.text, this.debit, this.credit);
}

/// One account of the huvudbok: its lines in date order and the sums.
class LedgerAccount {
  final int number;
  final String name;
  final List<LedgerLine> lines;
  const LedgerAccount(this.number, this.name, this.lines);

  Money get debit => Money.sum(lines.map((l) => l.debit));
  Money get credit => Money.sum(lines.map((l) => l.credit));

  /// Debit minus credit: positive for assets and costs, negative for debts,
  /// sales and VAT owed.
  Money get balance => debit - credit;
}

/// The ledger built from the verifications the app makes for the SIE file:
/// the same accounts and numbers, so the paper reports and the file agree.
/// Only what is registered in the app, no opening balances.
class Ledger {
  final List<SieVoucher> vouchers;
  final List<LedgerAccount> accounts;
  const Ledger._(this.vouchers, this.accounts);

  factory Ledger.of(List<SieVoucher> vouchers) {
    final lines = <int, List<LedgerLine>>{};
    final names = <int, String>{};
    for (final v in vouchers) {
      for (final r in v.lines) {
        names[r.account] ??= r.name;
        (lines[r.account] ??= []).add(LedgerLine('${v.series}${v.number}', v.date, v.text, r.debit, r.credit));
      }
    }
    final numbers = lines.keys.toList()..sort();
    return Ledger._(vouchers, [
      for (final n in numbers)
        LedgerAccount(n, names[n] ?? '', lines[n]!..sort((a, b) => a.date == b.date ? a.ver.compareTo(b.ver) : a.date.compareTo(b.date))),
    ]);
  }

  /// Debit minus credit of one account, zero when it has no transactions.
  Money balanceOf(int account) => Money.sum(accounts.where((a) => a.number == account).map((a) => a.balance));

  Money get totalDebit => Money.sum(accounts.map((a) => a.debit));
  Money get totalCredit => Money.sum(accounts.map((a) => a.credit));

  /// Every verification balances, so the trial balance does too.
  bool get balances => totalDebit == totalCredit;

  /// Sales (3xxx) as a positive amount.
  List<LedgerAccount> get incomeAccounts => [for (final a in accounts) if (a.number >= 3000 && a.number < 4000) a];

  /// Costs (4xxx to 7xxx) as a positive amount.
  List<LedgerAccount> get costAccounts => [for (final a in accounts) if (a.number >= 4000 && a.number < 8000) a];

  Money get income => -Money.sum(incomeAccounts.map((a) => a.balance));
  Money get costs => Money.sum(costAccounts.map((a) => a.balance));
  Money get result => income - costs;
}
