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
import 'app/biometric.dart';
import 'app/pin_lock.dart';
import 'ui/lock/pin_screens.dart';
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
  // Read before the first screen so a locked app never shows its content.
  final pinLock = PinLock(SecureLockStore(), biometric: PhoneBiometric());
  await pinLock.load();
  final themeMode = AppController.parseThemeMode(await repo.setting(SettingsKeys.themeMode));
  runApp(BokforingApp(
      controller: AppController(repo, reminders: reminders, autoBackup: autoBackup, pinLock: pinLock, themeMode: themeMode),
      setupDone: setupDone));
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
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: widget.controller.themeMode,
          builder: (context, mode, _) => MaterialApp(
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
          darkTheme: AppTheme.darkTheme(),
          themeMode: mode,
          // Every page and sheet ends above the phone's navigation buttons.
          builder: (context, child) {
            // The colours in AppTheme follow the resolved brightness.
            AppTheme.dark = Theme.of(context).brightness == Brightness.dark;
            final content = _Readable(
              child: ColoredBox(
                color: AppTheme.surface,
                child: _ThemeRefresh(
                  child: SafeArea(top: false, left: false, right: false, child: child ?? const SizedBox.shrink()),
                ),
              ),
            );
            final lock = widget.controller.pinLock;
            return lock == null ? content : AppLockGate(lock: lock, child: content);
          },
          home: _setupDone
              ? const Shell()
              : SetupWizard(onDone: () => setState(() => _setupDone = true)),
        ),
        ),
      );
}

/// The colours in AppTheme are read when a widget builds, so when the theme
/// changes every widget below is built again, also those that do not ask for
/// the theme themselves (and the ones kept alive in tabs).
class _ThemeRefresh extends StatefulWidget {
  final Widget child;
  const _ThemeRefresh({required this.child});

  @override
  State<_ThemeRefresh> createState() => _ThemeRefreshState();
}

class _ThemeRefreshState extends State<_ThemeRefresh> {
  Brightness? _seen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final b = Theme.of(context).brightness;
    if (_seen != null && _seen != b) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        void mark(Element e) {
          e.markNeedsBuild();
          e.visitChildren(mark);
        }

        (context as Element).visitChildren(mark);
      });
    }
    _seen = b;
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
      color: AppTheme.dark ? const Color(0xFF0B100E) : const Color(0xFFE6EBE5),
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
