import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../app_icons.dart';

/// The phone's permission to show notifications for Quee, as a switch. Android
/// only lets the app ask for it; turning it off is done in the phone's own
/// settings, so the switch takes the owner there. The state is read again when
/// the owner comes back.
class NotificationPermissionTile extends StatefulWidget {
  const NotificationPermissionTile({super.key});

  @override
  State<NotificationPermissionTile> createState() => _NotificationPermissionTileState();
}

class _NotificationPermissionTileState extends State<NotificationPermissionTile> with WidgetsBindingObserver {
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
    if (mounted) setState(() => _allowed = ok);
  }

  Future<void> _change(bool on) async {
    final reminders = AppScope.read(context).reminders;
    if (on) {
      // Android asks once or twice; after that only the phone's settings help.
      final ok = await reminders?.requestPermission() ?? false;
      await _read();
      if (!ok && mounted) await AppSettings.openAppSettings(type: AppSettingsType.notification);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Android låter bara dig stänga av aviseringar i telefonens inställningar. Där slår du av Quee.')));
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = _allowed;
    return SwitchListTile(
      secondary: Icon(AppIcons.notifications, color: allowed == null ? null : (allowed ? null : Theme.of(context).colorScheme.error)),
      title: const Text('Tillåt aviseringar i telefonen'),
      subtitle: Text(allowed == null
          ? ''
          : allowed
              ? 'Telefonen tillåter att Quee visar aviseringar.'
              : 'Aviseringar är blockerade i telefonen. Utan dem får du inga påminnelser.'),
      value: allowed ?? false,
      onChanged: allowed == null ? null : _change,
    );
  }
}
