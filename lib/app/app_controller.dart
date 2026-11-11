import 'package:flutter/widgets.dart';

import '../data/repository.dart';
import '../export/auto_backup.dart';
import '../notify/reminders.dart';
import 'pin_lock.dart';

/// Holds the repository and tells screens to reload after data changes.
class AppController extends ChangeNotifier {
  final Repository repo;
  final Reminders? reminders;

  /// Writes the automatic backup after changes, when it is turned on.
  final AutoBackup? autoBackup;

  /// The PIN that opens the app; null in tests.
  final PinLock? pinLock;
  AppController(this.repo, {this.reminders, this.autoBackup, this.pinLock});

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
