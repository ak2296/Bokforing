import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/pin_lock.dart';
import '../app_icons.dart';
import '../theme.dart';

/// Covers the whole app with the PIN screen while it is locked: at start, and
/// when the app comes back after more than [grace] in the background. The app
/// stays built underneath, so nothing is lost when it is unlocked.
class AppLockGate extends StatefulWidget {
  /// A file picker or the share sheet also sends the app to the background;
  /// returning from them within this time does not ask for the PIN again.
  static const grace = Duration(seconds: 60);

  final PinLock lock;
  final Widget child;
  const AppLockGate({super.key, required this.lock, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  late bool _locked = widget.lock.enabled;
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.lock.addListener(_changed);
  }

  @override
  void dispose() {
    widget.lock.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _changed() {
    if (!widget.lock.enabled && _locked) setState(() => _locked = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.lock.enabled) return;
    if (state == AppLifecycleState.paused) _leftAt ??= DateTime.now();
    if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left != null && DateTime.now().difference(left) > AppLockGate.grace) setState(() => _locked = true);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          Offstage(offstage: _locked, child: widget.child),
          if (_locked)
            Positioned.fill(
              child: PinScreen(
                lock: widget.lock,
                title: 'Quee är låst',
                onUnlocked: () => setState(() => _locked = false),
              ),
            ),
        ],
      );
}

String _waitText(Duration d) {
  final s = d.inSeconds < 1 ? 1 : d.inSeconds;
  return s >= 60 ? '${(s / 60).ceil()} min' : '$s s';
}

/// Asks for the PIN. Used as the lock screen and, with [onCancel], to confirm
/// a change of the lock.
class PinScreen extends StatefulWidget {
  final PinLock lock;
  final String title;
  final VoidCallback onUnlocked;
  final VoidCallback? onCancel;
  const PinScreen({super.key, required this.lock, required this.title, required this.onUnlocked, this.onCancel});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String _pin = '';
  String? _error;
  bool _busy = false;
  Duration _wait = Duration.zero;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _ready => !_busy && _wait == Duration.zero;

  void _add(String digit) {
    if (!_ready) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length >= widget.lock.pinLength) _check();
  }

  void _back() {
    if (_ready && _pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    final result = await widget.lock.verify(_pin);
    if (!mounted) return;
    switch (result.status) {
      case PinStatus.ok:
        widget.onUnlocked();
      case PinStatus.wrong:
        HapticFeedback.mediumImpact();
        setState(() {
          _pin = '';
          _busy = false;
          _error = 'Fel PIN-kod. ${result.triesLeft} försök kvar innan du får vänta.';
        });
      case PinStatus.locked:
        _startWait(result.wait);
    }
  }

  void _startWait(Duration wait) {
    _timer?.cancel();
    setState(() {
      _pin = '';
      _busy = false;
      _wait = wait;
      _error = null;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _wait -= const Duration(seconds: 1);
        if (_wait <= Duration.zero) {
          _wait = Duration.zero;
          t.cancel();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final message = _wait > Duration.zero ? 'För många försök. Försök igen om ${_waitText(_wait)}.' : _error;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(AppIcons.lock, size: 36, color: AppTheme.seed),
              const SizedBox(height: 12),
              Text(widget.title, style: t.titleLarge),
              const SizedBox(height: 4),
              Text('Skriv din PIN-kod', style: t.bodySmall),
              const SizedBox(height: 20),
              PinDots(total: widget.lock.pinLength, filled: _pin.length),
              SizedBox(
                height: 44,
                child: Center(
                  child: Text(message ?? '',
                      textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: AppTheme.pumpkinText)),
                ),
              ),
              PinKeypad(onDigit: _add, onBackspace: _back, enabled: _ready),
              if (widget.onCancel != null) TextButton(onPressed: widget.onCancel, child: const Text('Avbryt')),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Asks for the current PIN before a change. True when it was right.
Future<bool> confirmPin(BuildContext context, PinLock lock, {required String title}) async {
  final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
    builder: (c) => PinScreen(
      lock: lock,
      title: title,
      onUnlocked: () => Navigator.of(c).pop(true),
      onCancel: () => Navigator.of(c).pop(false),
    ),
  ));
  return ok ?? false;
}

/// Choose a new PIN, 4 to 6 digits, and type it twice. Pops true when saved.
class PinSetupPage extends StatefulWidget {
  /// Automatic backup is off: a forgotten PIN then means losing the data.
  final bool backupOff;
  final PinLock lock;
  const PinSetupPage({super.key, required this.lock, required this.backupOff});

  @override
  State<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends State<PinSetupPage> {
  String _pin = '';
  String _first = '';
  bool _confirming = false;
  String? _error;
  bool _saving = false;

  void _add(String digit) {
    if (_saving || _pin.length >= PinLock.maxLength) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
  }

  void _back() {
    if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _next() async {
    if (!_confirming) {
      setState(() {
        _first = _pin;
        _pin = '';
        _confirming = true;
      });
      return;
    }
    if (_pin != _first) {
      setState(() {
        _pin = '';
        _first = '';
        _confirming = false;
        _error = 'PIN-koderna var inte lika. Börja om.';
      });
      return;
    }
    setState(() => _saving = true);
    await widget.lock.setPin(_pin);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('PIN-kod')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Text(_confirming ? 'Skriv PIN-koden igen' : 'Välj en PIN-kod med 4 till 6 siffror', style: t.titleMedium),
            const SizedBox(height: 16),
            PinDots(total: math.max(PinLock.minLength, _pin.length), filled: _pin.length),
            SizedBox(
              height: 32,
              child: Center(
                child: Text(_error ?? '', style: t.bodySmall?.copyWith(color: AppTheme.pumpkinText)),
              ),
            ),
            PinKeypad(onDigit: _add, onBackspace: _back, enabled: !_saving),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _pin.length >= PinLock.minLength && !_saving ? _next : null,
              child: Text(_confirming ? 'Spara PIN-koden' : 'Fortsätt'),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.backupOff ? AppTheme.warningTint : AppTheme.tint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.backupOff
                    ? 'Glömmer du PIN-koden måste appen installeras om, och uppgifterna går förlorade om du inte har en '
                        'säkerhetskopia. Slå på automatisk säkerhetskopiering först.'
                    : 'Glömmer du PIN-koden måste appen installeras om och återställas från din säkerhetskopia.',
                style: t.bodySmall,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class PinDots extends StatelessWidget {
  final int total;
  final int filled;
  const PinDots({super.key, required this.total, required this.filled});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++)
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? AppTheme.seed : Colors.transparent,
                border: Border.all(color: AppTheme.seed, width: 1.5),
              ),
            ),
        ],
      );
}

class PinKeypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;
  const PinKeypad({super.key, required this.onDigit, required this.onBackspace, this.enabled = true});

  Widget _digit(String d) => SizedBox(
        width: 76,
        height: 64,
        child: TextButton(
          onPressed: enabled ? () => onDigit(d) : null,
          style: TextButton.styleFrom(shape: const CircleBorder(), foregroundColor: AppTheme.ink),
          child: Text(d, style: const TextStyle(fontSize: 26)),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) _digit(d)]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 76, height: 64),
            _digit('0'),
            SizedBox(
              width: 76,
              height: 64,
              child: IconButton(
                onPressed: enabled ? onBackspace : null,
                icon: const Icon(Icons.backspace_outlined, semanticLabel: 'Radera'),
              ),
            ),
          ]),
        ],
      );
}
