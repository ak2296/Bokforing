import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../app_icons.dart';
import '../theme.dart';

/// Whether the phone lets Quee show notifications, with one button: "Tillåt"
/// asks (or opens the phone's settings when Android no longer asks), and
/// "Telefonens inställningar" is the only place Android lets the owner turn
/// them off again. The state is read again when the owner comes back.
class NotificationPermissionTile extends StatefulWidget {
  /// Called with the current state each time it is read.
  final ValueChanged<bool>? onChanged;
  const NotificationPermissionTile({super.key, this.onChanged});

  @override
  State<NotificationPermissionTile> createState() =>
      _NotificationPermissionTileState();
}

class _NotificationPermissionTileState extends State<NotificationPermissionTile>
    with WidgetsBindingObserver {
  bool? _allowed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _read();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _read();
  }

  Future<void> _read() async {
    final ok = await AppScope.read(context).reminders?.allowed() ?? false;
    if (!mounted) return;
    setState(() => _allowed = ok);
    widget.onChanged?.call(ok);
  }

  Future<void> _allow() async {
    final granted =
        await AppScope.read(context).reminders?.requestPermission() ?? false;
    await _read();
    if (!granted) {
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = _allowed;
    final blocked = allowed == false;
    return ListTile(
      leading: Icon(
        blocked ? AppIcons.crossCircle : AppIcons.checkCircle,
        color: blocked ? AppTheme.danger : AppTheme.seed,
      ),
      title: const Text('Aviseringar i telefonen'),
      // One line is reserved while the state loads, so the row does not jump.
      subtitle: Text(
        allowed == null
            ? ' '
            : allowed
            ? 'Tillåtna. Stäng av dem i telefonens inställningar.'
            : 'Blockerade. Utan dem kommer inga påminnelser.',
      ),
      trailing: allowed == null
          ? null
          : allowed
          ? TextButton(
              onPressed: () => AppSettings.openAppSettings(
                type: AppSettingsType.notification,
              ),
              child: const Text('Inställningar'),
            )
          : FilledButton(onPressed: _allow, child: const Text('Tillåt')),
    );
  }
}
