import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/repository.dart';
import '../domain/dates.dart';
import '../domain/models.dart';

/// Payment reminders on the phone, scheduled locally (no internet). They
/// are rebuilt from the unpaid invoices whenever data changes.
class Reminders {
  static const enabledKey = 'reminders_enabled';
  static const daysKey = 'reminder_days';
  static const defaultDays = 3;
  static const hour = 9;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Europe/Stockholm'));
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
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
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'betalningar',
          'Påminnelser om betalning',
          channelDescription: 'Fakturor som snart ska betalas',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      );
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
    } catch (_) {
      // Never let a reminder problem stop the app or a save.
    }
  }
}
