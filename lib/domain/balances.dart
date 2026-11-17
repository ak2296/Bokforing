import 'dart:convert';

import 'ledger.dart';
import 'money.dart';

/// What an opening balance line is. The owner picks one; the BAS account
/// follows from it (and can be changed by the accountant).
enum BalanceKind {
  bank('Bankkonto', 1930, true),
  cash('Kassa', 1910, true),
  asset('Inventarier och utrustning', 1220, true),
  stock('Varulager', 1460, true),
  receivable('Kundfordran', 1510, true),
  loan('Lån', 2350, false),
  taxDebt('Skatteskuld', 2510, false),
  otherDebt('Annan skuld', 2890, false);

  final String label;
  final int account;
  final bool isAsset;
  const BalanceKind(this.label, this.account, this.isAsset);

  static BalanceKind byName(String? n) => values.firstWhere((k) => k.name == n, orElse: () => BalanceKind.otherDebt);
}

/// One line the owner has entered: a bank balance, an asset, a loan.
class BalanceEntry {
  final String id;
  final BalanceKind kind;
  final String name;
  final Money amount;

  /// Assets: the years left to write it off over. Loans: months left.
  final int? years;
  final int? monthsLeft;

  /// Loans: the yearly interest in percent.
  final double? ratePercent;
  const BalanceEntry({
    required this.id,
    required this.kind,
    required this.name,
    required this.amount,
    this.years,
    this.monthsLeft,
    this.ratePercent,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'ore': amount.ore,
        if (years != null) 'years': years,
        if (monthsLeft != null) 'months': monthsLeft,
        if (ratePercent != null) 'rate': ratePercent,
      };

  static BalanceEntry fromJson(Map<String, Object?> j) => BalanceEntry(
        id: '${j['id']}',
        kind: BalanceKind.byName(j['kind'] as String?),
        name: '${j['name'] ?? ''}',
        amount: Money((j['ore'] as num?)?.toInt() ?? 0),
        years: (j['years'] as num?)?.toInt(),
        monthsLeft: (j['months'] as num?)?.toInt(),
        ratePercent: (j['rate'] as num?)?.toDouble(),
      );
}

/// The balances the owner knows on one date. Equity is what is left when
/// debts are taken from assets, so the opening balance always balances.
class OpeningBalances {
  /// ISO date the balances are valid on, normally the first day of the financial year.
  final String date;
  final List<BalanceEntry> entries;
  const OpeningBalances(this.date, this.entries);

  bool get isEmpty => entries.isEmpty;

  Money get assets => Money.sum(entries.where((e) => e.kind.isAsset).map((e) => e.amount));
  Money get debts => Money.sum(entries.where((e) => !e.kind.isAsset).map((e) => e.amount));
  Money get equity => assets - debts;

  OpeningBalances withEntry(BalanceEntry e) {
    final i = entries.indexWhere((x) => x.id == e.id);
    final next = [...entries];
    i < 0 ? next.add(e) : next[i] = e;
    return OpeningBalances(date, next);
  }

  OpeningBalances without(String id) => OpeningBalances(date, [for (final e in entries) if (e.id != id) e]);
  OpeningBalances onDate(String d) => OpeningBalances(d, entries);

  String encode() => jsonEncode({'date': date, 'entries': [for (final e in entries) e.toJson()]});

  static OpeningBalances decode(String? text, {required String fallbackDate}) {
    if (text == null || text.isEmpty) return OpeningBalances(fallbackDate, const []);
    try {
      final j = jsonDecode(text) as Map<String, Object?>;
      return OpeningBalances('${j['date'] ?? fallbackDate}', [
        for (final e in (j['entries'] as List? ?? const [])) BalanceEntry.fromJson((e as Map).cast<String, Object?>()),
      ]);
    } on FormatException {
      return OpeningBalances(fallbackDate, const []);
    }
  }
}

/// One year of an asset's write-off, straight line over the years left.
class DepreciationYear {
  final int year;
  final Money amount;
  final Money valueAtEnd;
  const DepreciationYear(this.year, this.amount, this.valueAtEnd);
}

/// The straight-line plan for an asset from the balance date: the same amount
/// each year until nothing is left. A plan only; the accountant books it.
List<DepreciationYear> depreciationPlan(BalanceEntry e, int startYear) {
  final years = e.years;
  if (years == null || years <= 0 || e.amount.ore <= 0) return const [];
  final each = e.amount.ore ~/ years;
  var left = e.amount.ore;
  return [
    for (var i = 0; i < years; i++)
      () {
        final take = i == years - 1 ? left : each;
        left -= take;
        return DepreciationYear(startYear + i, Money(take), Money(left));
      }(),
  ];
}

/// The first month of a loan: what is paid back and the interest on what is left.
class LoanMonth {
  final Money amortisation;
  final Money interest;
  const LoanMonth(this.amortisation, this.interest);
}

LoanMonth? loanFirstMonth(BalanceEntry e) {
  final months = e.monthsLeft;
  if (months == null || months <= 0 || e.amount.ore <= 0) return null;
  final interest = (e.amount.ore * (e.ratePercent ?? 0) / 100 / 12).round();
  return LoanMonth(Money(e.amount.ore ~/ months), Money(interest));
}

/// One line of the balance sheet.
class BalanceRow {
  final String label;
  final Money amount;
  final bool strong;
  const BalanceRow(this.label, this.amount, {this.strong = false});
}

/// The Balansräkning draft on [asOf]: the opening balances plus the
/// verifications of the period, and the result so far in equity. Debts and
/// equity add up to the assets because every verification balances.
class BalanceSheet {
  final String asOf;
  final List<BalanceRow> assetRows;
  final List<BalanceRow> equityDebtRows;
  final Money totalAssets;
  final Money totalEquityDebts;
  const BalanceSheet(this.asOf, this.assetRows, this.equityDebtRows, this.totalAssets, this.totalEquityDebts);

  bool get balances => totalAssets == totalEquityDebts;

  factory BalanceSheet.build(OpeningBalances opening, Ledger movements, String asOf) {
    // Per account: what the owner entered plus what the verifications did.
    final bal = <int, Money>{};
    for (final e in opening.entries) {
      final sign = e.kind.isAsset ? 1 : -1;
      bal[e.kind.account] = (bal[e.kind.account] ?? Money.zero) + Money(sign * e.amount.ore);
    }
    for (final a in movements.accounts) {
      if (a.number >= 3000) continue;
      bal[a.number] = (bal[a.number] ?? Money.zero) + a.balance;
    }
    Money sum(bool Function(int) test, {bool credit = false}) {
      final s = Money.sum([for (final e in bal.entries) if (test(e.key)) e.value]);
      return credit ? -s : s;
    }

    final fixed = sum((n) => n >= 1000 && n < 1400);
    final stock = sum((n) => n >= 1400 && n < 1500);
    final receivables = sum((n) => n >= 1500 && n < 1900);
    final cash = sum((n) => n >= 1900 && n < 2000);
    final assetsTotal = fixed + stock + receivables + cash;

    final loans = sum((n) => n >= 2300 && n < 2400, credit: true);
    final suppliers = sum((n) => n >= 2400 && n < 2500, credit: true);
    final taxes = sum((n) => n >= 2500 && n < 2600, credit: true);
    final vat = sum((n) => n >= 2600 && n < 2700, credit: true);
    final payroll = sum((n) => n >= 2700 && n < 2800, credit: true);
    final otherDebts = sum((n) => n >= 2800 && n < 3000, credit: true);
    final debtsTotal = loans + suppliers + taxes + vat + payroll + otherDebts;

    // What the owner paid privately for the company (enskild firma: egen insättning).
    final deposits = sum((n) => n >= 2000 && n < 2300, credit: true);
    final openingEquity = opening.equity;
    final result = movements.result;
    final equityTotal = openingEquity + result + deposits;

    BalanceRow? row(String label, Money m) => m.isZero ? null : BalanceRow(label, m);
    return BalanceSheet(
      asOf,
      [
        ?row('Inventarier och utrustning', fixed),
        ?row('Varulager', stock),
        ?row('Fordringar', receivables),
        ?row('Kassa och bank', cash),
      ],
      [
        BalanceRow('Eget kapital vid årets början', openingEquity),
        BalanceRow('Resultat hittills i år', result),
        ?row('Egna insättningar', deposits),
        BalanceRow('Summa eget kapital', equityTotal, strong: true),
        ?row('Lån', loans),
        ?row('Leverantörsskulder', suppliers),
        ?row('Skatteskulder', taxes),
        ?row('Moms', vat),
        ?row('Personalskatt och avgifter', payroll),
        ?row('Övriga skulder', otherDebts),
      ],
      assetsTotal,
      equityTotal + debtsTotal,
    );
  }
}
