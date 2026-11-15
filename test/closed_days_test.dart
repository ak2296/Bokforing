import 'package:bokforing/domain/closed_days.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('5 of 6 on the 6th: five scanned, the 6th still open', () {
    final c = ZCoverage.of(
      year: 2026, month: 11, today: DateTime(2026, 11, 6),
      scannedDates: {'2026-11-01', '2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05'},
      closed: const ClosedDays(),
    );
    expect(c.text, '5 av 6');
    expect(c.missing, isEmpty); // today is not missing yet
  });

  test('a day without a Z-report before today is missing, a closed day is not', () {
    final c = ZCoverage.of(
      year: 2026, month: 10, today: DateTime(2026, 10, 20),
      scannedDates: {for (var d = 1; d <= 19; d++) '2026-10-${d.toString().padLeft(2, '0')}'}..remove('2026-10-18')..remove('2026-10-12'),
      closed: const ClosedDays(dates: {'2026-10-12'}),
    );
    expect(c.missing, ['2026-10-18']);
    expect(c.text, '17 av 19');
  });

  test('a closed weekday does not count and a Z-report on it still does', () {
    // 2026-11-02 is a Monday.
    final c = ZCoverage.of(
      year: 2026, month: 11, today: DateTime(2026, 11, 4),
      scannedDates: {'2026-11-01', '2026-11-03'},
      closed: const ClosedDays(weekdays: {1}),
    );
    expect(c.text, '2 av 3');
    expect(c.missing, isEmpty);
    final withMonday = ZCoverage.of(
      year: 2026, month: 11, today: DateTime(2026, 11, 4),
      scannedDates: {'2026-11-01', '2026-11-02', '2026-11-03'},
      closed: const ClosedDays(weekdays: {1}),
    );
    expect(withMonday.text, '3 av 4');
  });

  test('a past month counts all its days', () {
    final c = ZCoverage.of(year: 2026, month: 2, today: DateTime(2026, 11, 6), scannedDates: {}, closed: const ClosedDays());
    expect(c.days, 28);
    expect(c.missing.length, 28);
  });

  test('closed days are saved and read back, damaged data gives none', () {
    const c = ClosedDays(weekdays: {1, 7}, dates: {'2026-12-24'});
    final back = ClosedDays.decode(c.encodeWeekdays(), c.encodeDates());
    expect(back.weekdays, {1, 7});
    expect(back.dates, {'2026-12-24'});
    expect(ClosedDays.decode('x', 'y').weekdays, isEmpty);
  });
}
