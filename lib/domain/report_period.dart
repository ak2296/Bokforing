import 'dates.dart';

/// How much time a report covers. Quarter and half-year follow the financial
/// year (a calendar year unless the owner set another start month).
enum PeriodKind {
  month('Månad', 1),
  quarter('Kvartal', 3),
  half('Halvår', 6),
  year('År', 12);

  final String label;
  final int months;
  const PeriodKind(this.label, this.months);

  static PeriodKind byName(String? n) => values.firstWhere((k) => k.name == n, orElse: () => PeriodKind.month);
}

/// One month, quarter, half-year or financial year, with the dates and names
/// reports and the package need.
class ReportPeriod {
  final PeriodKind kind;

  /// The calendar year the financial year starts in.
  final int fyStartYear;

  /// 0-based place inside the financial year: 0..11 months, 0..3 quarters, 0..1 halves, 0 the year.
  final int slot;

  /// The month the financial year starts in (1 = January).
  final int startMonth;
  const ReportPeriod(this.kind, this.fyStartYear, this.slot, this.startMonth);

  /// The period of [kind] that [date] falls in.
  factory ReportPeriod.containing(PeriodKind kind, DateTime date, int startMonth) {
    final fy = date.month >= startMonth ? date.year : date.year - 1;
    final into = (date.year - fy) * 12 + date.month - startMonth;
    return ReportPeriod(kind, fy, into ~/ kind.months, startMonth);
  }

  int get _perYear => 12 ~/ kind.months;

  DateTime get fromDate => DateTime(fyStartYear, startMonth + slot * kind.months, 1);
  DateTime get toDate => DateTime(fyStartYear, startMonth + (slot + 1) * kind.months, 0);
  String get from => SwedishDates.iso(fromDate);
  String get to => SwedishDates.iso(toDate);

  /// The whole financial year this period is in.
  String get yearFrom => SwedishDates.iso(DateTime(fyStartYear, startMonth, 1));
  String get yearTo => SwedishDates.iso(DateTime(fyStartYear, startMonth + 12, 0));

  /// The (year, month) pairs the period holds, in order.
  List<(int, int)> get months {
    final a = fromDate;
    return [
      for (var i = 0; i < kind.months; i++) () {
        final d = DateTime(a.year, a.month + i, 1);
        return (d.year, d.month);
      }(),
    ];
  }

  String get title {
    final a = fromDate, b = toDate;
    String short(DateTime d) => SwedishDates.shortMonths[d.month - 1];
    return switch (kind) {
      PeriodKind.month => '${SwedishDates.capitalize(SwedishDates.months[a.month - 1])} ${a.year}',
      PeriodKind.quarter => 'Kvartal ${slot + 1}, ${short(a)}–${short(b)} ${b.year}',
      PeriodKind.half => 'Halvår ${slot + 1}, ${short(a)}–${short(b)} ${b.year}',
      PeriodKind.year => startMonth == 1 ? 'Året ${a.year}' : 'Räkenskapsåret $from – $to',
    };
  }

  /// For file names.
  String get fileTag => switch (kind) {
        PeriodKind.month => '${fromDate.year}-${fromDate.month.toString().padLeft(2, '0')}',
        PeriodKind.quarter => '${toDate.year}-K${slot + 1}',
        PeriodKind.half => '${toDate.year}-H${slot + 1}',
        PeriodKind.year => startMonth == 1 ? '$fyStartYear' : '$fyStartYear-${fyStartYear + 1}',
      };

  ReportPeriod step(int delta) {
    var fy = fyStartYear;
    var s = slot + delta;
    while (s < 0) {
      s += _perYear;
      fy--;
    }
    while (s >= _perYear) {
      s -= _perYear;
      fy++;
    }
    return ReportPeriod(kind, fy, s, startMonth);
  }

  /// The period of another kind that holds the start of this one.
  ReportPeriod inKind(PeriodKind other) => ReportPeriod.containing(other, fromDate, startMonth);

  @override
  bool operator ==(Object other) =>
      other is ReportPeriod && other.kind == kind && other.fyStartYear == fyStartYear && other.slot == slot;

  @override
  int get hashCode => Object.hash(kind, fyStartYear, slot);
}
