import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';

import '../data/repository.dart';
import '../export/auto_backup.dart';
import '../notify/reminders.dart';
import 'pin_lock.dart';
import 'settings_keys.dart';

/// Holds the repository and tells screens to reload after data changes.
class AppController extends ChangeNotifier {
  final Repository repo;
  final Reminders? reminders;

  /// Writes the automatic backup after changes, when it is turned on.
  final AutoBackup? autoBackup;

  /// The PIN that opens the app; null in tests.
  final PinLock? pinLock;
  AppController(this.repo, {this.reminders, this.autoBackup, this.pinLock, ThemeMode themeMode = ThemeMode.system})
      : themeMode = ValueNotifier(themeMode);

  /// Ljust, Mörkt or follow the phone.
  final ValueNotifier<ThemeMode> themeMode;

  static ThemeMode parseThemeMode(String? v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    await repo.setSetting(SettingsKeys.themeMode, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'auto',
    });
  }

  int _revision = 0;
  int get revision => _revision;

  void dataChanged() {
    _revision++;
    notifyListeners();
    // Payment reminders follow the unpaid invoices.
    reminders?.reschedule(repo);
    autoBackup?.schedule();
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child})
      : super(notifier: controller);

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Read without subscribing to changes (for callbacks).
  static AppController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
