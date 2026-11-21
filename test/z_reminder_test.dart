import 'package:bokforing/domain/closed_days.dart';
import 'package:bokforing/notify/reminders.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Friday 2026-11-20, 10:00.
  final now = DateTime(2026, 11, 20, 10);
  const none = ClosedDays();

  test('the evening after: a missing day is reminded at 18:00 the next day', () {
    final t = Reminders.zTimes(now, {'2026-11-14', '2026-11-15', '2026-11-16', '2026-11-17', '2026-11-18', '2026-11-19'}, none, 1);
    // 13 nov (a week back) would remind on the 14th: already past. 20 nov (today) reminds on the 21st.
    expect(t.map((e) => '${e.$1.toIso8601String()} ${e.$2.join(',')}'), ['${DateTime(2026, 11, 21, 18).toIso8601String()} 2026-11-20']);
  });

  test('a day with a Z-report, or a closed day, gets no reminder', () {
    final closed = const ClosedDays(weekdays: {7}, dates: {'2026-11-19'});
    final t = Reminders.zTimes(now, {'2026-11-20'}, closed, 1);
    final days = t.expand((e) => e.$2).toSet();
    expect(days.contains('2026-11-20'), isFalse);
    expect(days.contains('2026-11-19'), isFalse);
    // 22 nov 2026 is a Sunday, but only days up to today count anyway; 15 nov is a Sunday.
    expect(days.contains('2026-11-15'), isFalse);
  });

  test('days that fall on the same evening are given together', () {
    // 18 and 19 nov missing, delay 2: reminders on 20 nov 18:00 and 21 nov 18:00.
    final t = Reminders.zTimes(now, {for (var d = 13; d <= 17; d++) '2026-11-$d', '2026-11-20'}, none, 2);
    expect(t.map((e) => '${e.$1.toIso8601String()} ${e.$2.join(',')}'), [
      '${DateTime(2026, 11, 20, 18).toIso8601String()} 2026-11-18',
      '${DateTime(2026, 11, 21, 18).toIso8601String()} 2026-11-19',
    ]);
  });

  test('same evening: today is reminded at 18:00 today, and not after 18:00', () {
    expect(Reminders.zTimes(now, {for (var d = 13; d <= 19; d++) '2026-11-$d'}, none, 0).single.$1, DateTime(2026, 11, 20, 18));
    expect(Reminders.zTimes(DateTime(2026, 11, 20, 19), {for (var d = 13; d <= 19; d++) '2026-11-$d'}, none, 0), isEmpty);
  });
}
