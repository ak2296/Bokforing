import 'dart:convert';

import 'dates.dart';

/// The days the shop was closed, so no Z-report is expected: whole weekdays that
/// are always closed (Monday = 1) and single dates (a holiday, an unplanned
/// closing).
class ClosedDays {
  final Set<int> weekdays;
  final Set<String> dates;
  const ClosedDays({this.weekdays = const {}, this.dates = const {}});

  bool isClosed(DateTime day) => weekdays.contains(day.weekday) || dates.contains(SwedishDates.iso(day));

  ClosedDays withDate(String iso) => ClosedDays(weekdays: weekdays, dates: {...dates, iso});
  ClosedDays withoutDate(String iso) => ClosedDays(weekdays: weekdays, dates: {...dates}..remove(iso));
  ClosedDays withWeekdays(Set<int> days) => ClosedDays(weekdays: days, dates: dates);

  String encodeWeekdays() => jsonEncode(weekdays.toList()..sort());
  String encodeDates() => jsonEncode(dates.toList()..sort());

  static ClosedDays decode(String? weekdaysJson, String? datesJson) {
    Set<T> list<T>(String? json) {
      if (json == null || json.isEmpty) return <T>{};
      try {
        return (jsonDecode(json) as List).whereType<T>().toSet();
      } on Object {
        return <T>{};
      }
    }

    return ClosedDays(weekdays: list<int>(weekdaysJson).where((d) => d >= 1 && d <= 7).toSet(), dates: list<String>(datesJson));
  }
}

/// How many Z-reports a month has against the days that should have one.
class ZCoverage {
  /// Days with a Z-report, and the days that count: every day from the 1st up to
  /// today (or the month's last day) that is not closed, plus any closed day that
  /// has a Z-report anyway.
  final int scanned;
  final int days;

  /// Days before today that count but have no Z-report, oldest first (ISO).
  final List<String> missing;
  const ZCoverage(this.scanned, this.days, this.missing);

  String get text => '$scanned av $days';

  factory ZCoverage.of({
    required int year,
    required int month,
    required DateTime today,
    required Set<String> scannedDates,
    required ClosedDays closed,
  }) {
    final last = DateTime(year, month + 1, 0).day;
    final upTo = DateTime(today.year, today.month, today.day);
    var scanned = 0, days = 0;
    final missing = <String>[];
    for (var d = 1; d <= last; d++) {
      final day = DateTime(year, month, d);
      if (day.isAfter(upTo)) break;
      final iso = SwedishDates.iso(day);
      final has = scannedDates.contains(iso);
      if (has) {
        scanned++;
        days++;
      } else if (!closed.isClosed(day)) {
        days++;
        if (day.isBefore(upTo)) missing.add(iso);
      }
    }
    return ZCoverage(scanned, days, missing);
  }
}
