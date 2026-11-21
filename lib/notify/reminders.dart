import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/repository.dart';
import '../domain/closed_days.dart';
import '../domain/dates.dart';
import '../domain/models.dart';

/// Payment reminders on the phone, scheduled locally (no internet). They
/// are rebuilt from the unpaid invoices whenever data changes.
class Reminders {
  static const enabledKey = 'reminders_enabled';
  static const daysKey = 'reminder_days';
  static const defaultDays = 3;
  static const hour = 9;

  /// The reminder about a missing Z-report: how many days after the day it comes
  /// (0 the same evening, 1 the evening after, 2 two evenings after), or 'off'. The owner
  /// may scan the day after, so the default is the evening after, at 18:00.
  static const zDelayKey = 'z_reminder_delay';
  static const zHour = 18;
  static const defaultZDelay = 1;

  /// The saved choice: days after, or null when the reminder is off.
  static Future<int?> zDelay(Repository repo) async {
    final raw = await repo.setting(zDelayKey);
    if (raw == 'off') return null;
    return int.tryParse(raw ?? '')?.clamp(0, 2) ?? defaultZDelay;
  }

  /// When to remind about days without a Z-report: for each open day of the last week that
  /// has none, at [zHour] [delay] days later, if that is still ahead. Several days that fall
  /// on the same evening are given together, so one notification says it all.
  static List<(DateTime, List<String>)> zTimes(DateTime now, Set<String> scanned, ClosedDays closed, int delay) {
    final today = DateTime(now.year, now.month, now.day);
    final byTime = <DateTime, List<String>>{};
    for (var back = 7; back >= 0; back--) {
      final day = today.subtract(Duration(days: back));
      final iso = SwedishDates.iso(day);
      if (scanned.contains(iso) || closed.isClosed(day)) continue;
      final at = DateTime(day.year, day.month, day.day + delay, zHour);
      if (at.isAfter(now)) (byTime[at] ??= []).add(iso);
    }
    return [for (final e in byTime.entries) (e.key, e.value)];
  }

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Europe/Stockholm'));
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_quee')),
      );
      _ready = true;
    } catch (_) {
      // Reminders are a convenience; the app works without them.
      _ready = false;
    }
  }

  /// Asks for the notification permission (Android 13+). Returns whether
  /// notifications are allowed.
  Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  /// Whether the phone lets Quee show notifications right now.
  Future<bool> allowed() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? true;
  }

  /// A new channel id: Android keeps the importance a channel had when it was first
  /// made, so the old "betalningar" (default importance, launcher icon) cannot be
  /// changed. High importance shows the notification on top and in the status bar.
  static const _channelId = 'betalningar_v2';
  static const details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Påminnelser om betalning',
      channelDescription: 'Fakturor som snart ska betalas',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_quee',
      color: Color(0xFF0B6B4E),
      category: AndroidNotificationCategory.reminder,
    ),
  );

  /// TEMP: remove after the notification test on the owner's phone. Shows one
  /// notification now and schedules a second one in a minute, the same way the real
  /// reminders are scheduled, so both paths can be checked.
  Future<void> sendTest() async {
    await init();
    await _plugin.show(id: 999001, title: 'Test: Quee', body: 'Så här ser en direkt avisering ut.', notificationDetails: details);
    await _plugin.zonedSchedule(
      id: 999002,
      title: 'Test: Quee, schemalagd',
      body: 'Den här kom en stund efter att du tryckte. Så kommer påminnelserna.',
      scheduledDate: tz.TZDateTime.now(tz.local).add(const Duration(minutes: 1)),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static const zDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'zrapporter',
      'Påminnelser om Z-rapporter',
      channelDescription: 'Dagar där Z-rapporten inte är skannad',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_quee',
      color: Color(0xFF0B6B4E),
      category: AndroidNotificationCategory.reminder,
    ),
  );

  static Future<bool> enabled(Repository repo) => repo.boolSetting(enabledKey, fallback: true);

  static Future<int> days(Repository repo) async => int.tryParse(await repo.setting(daysKey) ?? '') ?? defaultDays;

  /// When reminders for [inv] fire: [daysBefore] days before the due date
  /// and on the due date, at 09:00, only if still in the future.
  static List<DateTime> times(Invoice inv, int daysBefore, DateTime now) {
    final due = inv.dueDate == null ? null : SwedishDates.parseIso(inv.dueDate!);
    if (inv.paid || due == null) return const [];
    final out = <DateTime>[];
    for (final d in {daysBefore, 0}) {
      final at = DateTime(due.year, due.month, due.day - d, hour);
      if (at.isAfter(now)) out.add(at);
    }
    return out;
  }

  Future<void> reschedule(Repository repo) async {
    await init();
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      if (!await enabled(repo)) return;
      final daysBefore = await days(repo);
      final now = DateTime.now();
      for (final inv in await repo.unpaidInvoices()) {
        final at = times(inv, daysBefore, now);
        for (var k = 0; k < at.length; k++) {
          final onDueDay = at[k].day == SwedishDates.parseIso(inv.dueDate!)!.day &&
              at[k].month == SwedishDates.parseIso(inv.dueDate!)!.month;
          await _plugin.zonedSchedule(
            id: inv.id! * 10 + k,
            title: onDueDay ? 'Faktura förfaller i dag' : 'Faktura förfaller snart',
            body: '${inv.supplier.isEmpty ? 'Faktura' : inv.supplier}: ${inv.total.format()} '
                'förfaller ${SwedishDates.mediumDay(inv.dueDate!)}.',
            scheduledDate: tz.TZDateTime.from(at[k], tz.local),
            notificationDetails: details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      }
      await _scheduleZ(repo, now);
    } catch (_) {
      // Never let a reminder problem stop the app or a save.
    }
  }

  /// Reminders for days without a Z-report. Rebuilt with the payment reminders, so a
  /// Z-report scanned in the meantime cancels its reminder.
  Future<void> _scheduleZ(Repository repo, DateTime now) async {
    final delay = await zDelay(repo);
    if (delay == null) return;
    final today = DateTime(now.year, now.month, now.day);
    final sales = await repo.dailySalesBetween(SwedishDates.iso(today.subtract(const Duration(days: 7))), SwedishDates.iso(today));
    final times = zTimes(now, {for (final d in sales) d.businessDate}, await repo.closedDays(), delay);
    for (final (i, (at, days)) in times.indexed) {
      final names = days.map(SwedishDates.mediumDay).join(', ');
      await _plugin.zonedSchedule(
        id: 900000 + i,
        title: days.length == 1 ? 'Z-rapport saknas' : 'Z-rapporter saknas',
        body: 'Du har inte skannat Z-rapporten för $names.',
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        notificationDetails: zDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}
