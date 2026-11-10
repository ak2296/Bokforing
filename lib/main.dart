import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_controller.dart';
import 'app/settings_keys.dart';
import 'data/database.dart';
import 'data/storage.dart';
import 'export/auto_backup.dart';
import 'data/repository.dart';
import 'notify/reminders.dart';
import 'ui/setup_wizard.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  final repo = Repository(db);
  // Photos left behind by a scan that was closed without saving.
  AppStorage.cleanTemp();
  final setupDone = await repo.boolSetting(SettingsKeys.setupDone);
  final reminders = Reminders();
  await reminders.init();
  reminders.reschedule(repo);
  final autoBackup = AutoBackup(repo);
  // Catches up on changes made just before the app was closed last time.
  autoBackup.runQuietly(onlyIfPending: true);
  runApp(BokforingApp(
      controller: AppController(repo, reminders: reminders, autoBackup: autoBackup), setupDone: setupDone));
}

class BokforingApp extends StatefulWidget {
  final AppController controller;
  final bool setupDone;
  const BokforingApp({super.key, required this.controller, required this.setupDone});

  @override
  State<BokforingApp> createState() => _BokforingAppState();
}

class _BokforingAppState extends State<BokforingApp> {
  late bool _setupDone = widget.setupDone;

  @override
  Widget build(BuildContext context) => AppScope(
        controller: widget.controller,
        child: MaterialApp(
          title: 'Quee',
          debugShowCheckedModeBanner: false,
          locale: const Locale('sv', 'SE'),
          supportedLocales: const [Locale('sv', 'SE')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light(),
          // Every page and sheet ends above the phone's navigation buttons.
          builder: (context, child) => _Readable(
            child: ColoredBox(
              color: Colors.white,
              child: SafeArea(top: false, left: false, right: false, child: child ?? const SizedBox.shrink()),
            ),
          ),
          home: _setupDone
              ? const Shell()
              : SetupWizard(onDone: () => setState(() => _setupDone = true)),
        ),
      );
}

/// On a tablet the screens keep a comfortable reading width in the middle,
/// instead of lines and tables stretched across the whole display.
class _Readable extends StatelessWidget {
  static const maxWidth = 840.0;
  final Widget child;
  const _Readable({required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width <= maxWidth) return child;
    final side = (mq.size.width - maxWidth) / 2;
    return ColoredBox(
      color: const Color(0xFFE6EBE5),
      child: Center(
        child: SizedBox(
          width: maxWidth,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 24)],
            ),
            child: MediaQuery(
              data: mq.copyWith(
                size: Size(maxWidth, mq.size.height),
                padding: mq.padding.copyWith(
                  left: math.max(0.0, mq.padding.left - side),
                  right: math.max(0.0, mq.padding.right - side),
                ),
              ),
              child: ClipRect(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
