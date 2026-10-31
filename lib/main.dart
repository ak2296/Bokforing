import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_controller.dart';
import 'app/settings_keys.dart';
import 'data/database.dart';
import 'data/repository.dart';
import 'notify/reminders.dart';
import 'ui/setup_wizard.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  final repo = Repository(db);
  final setupDone = await repo.boolSetting(SettingsKeys.setupDone);
  final reminders = Reminders();
  await reminders.init();
  reminders.reschedule(repo);
  runApp(BokforingApp(controller: AppController(repo, reminders: reminders), setupDone: setupDone));
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
          title: 'Bokföringsassistent',
          debugShowCheckedModeBanner: false,
          locale: const Locale('sv', 'SE'),
          supportedLocales: const [Locale('sv', 'SE')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light(),
          home: _setupDone
              ? const Shell()
              : SetupWizard(onDone: () => setState(() => _setupDone = true)),
        ),
      );
}
