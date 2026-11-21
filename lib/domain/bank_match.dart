import 'bank_statement.dart';
import 'dates.dart';
import 'models.dart';
import 'money.dart';

/// One line on the page "Z-rapporter mot bank": either a bank deposit that equals the
/// card and Swish takings of one or more Z-report days (minus the card company's fee),
/// or Z-report days that no deposit was found for.
class ZBankLine {
  /// The Z-report days (ISO), oldest first.
  final List<String> days;

  /// What the Z-reports say was paid by card and Swish for those days.
  final Money expected;

  /// The bank row that paid them, or null when none was found.
  final BankRow? deposit;

  /// True when the days are so recent that the money may not have arrived yet.
  final bool pending;
  const ZBankLine(this.days, this.expected, this.deposit, {this.pending = false});

  bool get matched => deposit != null;

  /// Expected minus deposited: the card company's fee.
  Money get fee => deposit == null ? Money.zero : expected - deposit!.amount;
}

/// Matching of card takings against a bank file (payments of invoices are matched by
/// bank_matcher.dart). Works in memory on the rows of the file; the caller decides what
/// to keep.
class ZBankMatcher {
  const ZBankMatcher._();

  /// The card company pays out several days of card takings at once and keeps a fee, so
  /// a deposit is taken to pay the oldest still unpaid run of Z-report days when it is
  /// at most [maxFee] (6 %) below the run's card total, and not above it.
  static const maxFee = 0.06;

  /// A run is at most this many days long.
  static const maxRun = 7;

  /// Days younger than this have no deposit yet and are shown as waiting.
  static const waitDays = 5;

  static List<ZBankLine> matchZ(List<DailySales> sales, List<BankRow> bank, {DateTime? today}) {
    final days = [for (final d in sales) if ((d.card ?? Money.zero) > Money.zero) d]
      ..sort((a, b) => a.businessDate.compareTo(b.businessDate));
    final deposits = [for (final r in bank) if (r.amount > Money.zero) r]..sort((a, b) => a.date.compareTo(b.date));
    final used = <String>{};
    final lines = <ZBankLine>[];

    for (final dep in deposits) {
      final open = [for (final d in days) if (!used.contains(d.businessDate) && d.businessDate.compareTo(dep.date) <= 0) d];
      if (open.isEmpty) continue;
      // The oldest open day, or the one after it when the oldest was paid some other way.
      for (var start = 0; start < open.length && start < 3; start++) {
        var sum = Money.zero;
        List<DailySales>? hit;
        for (var n = 0; n < maxRun && start + n < open.length; n++) {
          sum += open[start + n].card!;
          if (dep.amount <= sum && dep.amount.ore >= sum.ore * (1 - maxFee)) {
            hit = open.sublist(start, start + n + 1);
            break;
          }
        }
        if (hit != null) {
          used.addAll(hit.map((d) => d.businessDate));
          lines.add(ZBankLine([for (final d in hit) d.businessDate], Money.sum(hit.map((d) => d.card!)), dep));
          break;
        }
      }
    }

    final now = today ?? DateTime.now();
    final left = [for (final d in days) if (!used.contains(d.businessDate)) d];
    // Group the unpaid days that follow each other into one line.
    var i = 0;
    while (i < left.length) {
      var j = i;
      while (j + 1 < left.length && _daysBetween(left[j].businessDate, left[j + 1].businessDate) <= 1) {
        j++;
      }
      final run = left.sublist(i, j + 1);
      final last = SwedishDates.parseIso(run.last.businessDate)!;
      lines.add(ZBankLine([for (final d in run) d.businessDate], Money.sum(run.map((d) => d.card!)), null,
          pending: now.difference(last).inDays < waitDays));
      i = j + 1;
    }
    lines.sort((a, b) => a.days.first.compareTo(b.days.first));
    return lines;
  }

  static int _daysBetween(String a, String b) => SwedishDates.parseIso(b)!.difference(SwedishDates.parseIso(a)!).inDays;
}
