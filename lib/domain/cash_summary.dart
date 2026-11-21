import 'models.dart';
import 'money.dart';
import 'pay_method.dart';

/// Cash and card for a period, from what is registered: takings from the Z-reports
/// (cash, and card including Swish) and what the registered invoices and receipts
/// were paid with. "Netto", not a balance: the app has no opening cash, and cash
/// deposits, wages and withdrawals are not in it.
class CashSummary {
  /// Z-report cash and card/Swish, only from reports that carry those figures.
  final Money cashIn;
  final Money cardIn;

  /// Expenses paid in cash from the till, with the company's bank or card, and with
  /// the owner's own money. The app cannot tell a card payment from a bank transfer:
  /// both are "Bank / kort".
  final Money cashOut;
  final Money bankOut;
  final Money ownerOut;

  /// Z-reports in the period, and how many of them carry cash or card figures.
  final int zDays;
  final int zDaysWithPayments;
  const CashSummary({
    required this.cashIn,
    required this.cardIn,
    required this.cashOut,
    required this.bankOut,
    required this.ownerOut,
    required this.zDays,
    required this.zDaysWithPayments,
  });

  /// Cash in minus cash out.
  Money get cashLeft => cashIn - cashOut;

  /// Card and Swish takings minus what was paid from the bank or by card.
  Money get bankNet => cardIn - bankOut;

  /// Z-reports without cash or card figures (older ones): the totals miss them.
  int get zDaysWithoutPayments => zDays - zDaysWithPayments;

  factory CashSummary.of(List<DailySales> sales, List<Invoice> invoices) {
    Money sum(Iterable<Money> v) => Money.sum(v);
    Money paidWith(PayMethod m) => sum([
      for (final i in invoices)
        if (i.paid)
          for (final p in i.parts)
          if (p.method == m) p.amount,
    ]);
    return CashSummary(
      cashIn: sum(sales.map((d) => d.cash ?? Money.zero)),
      cardIn: sum(sales.map((d) => d.card ?? Money.zero)),
      cashOut: paidWith(PayMethod.cash),
      bankOut: paidWith(PayMethod.bank),
      ownerOut: paidWith(PayMethod.owner),
      zDays: sales.length,
      zDaysWithPayments: sales.where((d) => d.hasCashData).length,
    );
  }
}
