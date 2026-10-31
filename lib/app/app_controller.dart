import 'package:flutter/widgets.dart';

import '../data/repository.dart';

/// Holds the repository and tells screens to reload after data changes.
class AppController extends ChangeNotifier {
  final Repository repo;
  AppController(this.repo);

  int _revision = 0;
  int get revision => _revision;

  void dataChanged() {
    _revision++;
    notifyListeners();
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
