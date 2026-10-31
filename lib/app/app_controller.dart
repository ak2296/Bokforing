import 'package:flutter/widgets.dart';

import '../data/repository.dart';
import '../notify/reminders.dart';

/// Holds the repository and tells screens to reload after data changes.
class AppController extends ChangeNotifier {
  final Repository repo;
  final Reminders? reminders;
  AppController(this.repo, {this.reminders});

  int _revision = 0;
  int get revision => _revision;

  void dataChanged() {
    _revision++;
    notifyListeners();
    // Payment reminders follow the unpaid invoices.
    reminders?.reschedule(repo);
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
