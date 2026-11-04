import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../domain/license.dart';
import '../theme.dart';

String licenseStatusText(LicenseState s) => switch (s.status) {
      LicenseStatus.active => s.license?.until == null
          ? 'Aktiverad, inget slutdatum'
          : 'Aktiverad till ${s.license!.until}',
      LicenseStatus.missing => 'Inte aktiverad',
      LicenseStatus.expired => 'Koden gick ut ${s.license?.until ?? ''}',
      LicenseStatus.revoked => 'Koden är avslutad',
    };

/// True when new papers may be saved. Otherwise says why and offers to
/// activate. Viewing, reports, PDF and backup always keep working.
Future<bool> requireLicense(BuildContext context) async {
  final state = await AppScope.read(context).repo.licenseState();
  if (state.status == LicenseStatus.active || !context.mounted) return state.status == LicenseStatus.active;
  final activate = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Appen behöver aktiveras'),
      content: Text('${licenseStatusText(state)}. Du kan fortfarande se allt, skapa rapporter och göra säkerhetskopior, '
          'men inte registrera nya papper.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Inte nu')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Aktivera')),
      ],
    ),
  );
  if (activate == true && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ActivationPage()));
    if (context.mounted) {
      return (await AppScope.read(context).repo.licenseState()).status == LicenseStatus.active;
    }
  }
  return false;
}

class ActivationPage extends StatefulWidget {
  const ActivationPage({super.key});

  @override
  State<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends State<ActivationPage> {
  final _code = TextEditingController();
  LicenseState? _state;
  String? _error;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_state == null) _load();
  }

  Future<void> _load() async {
    final s = await AppScope.read(context).repo.licenseState();
    if (mounted) setState(() => _state = s);
  }

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = AppScope.read(context);
    final error = await controller.repo.activateLicense(_code.text);
    if (!mounted) return;
    if (error == null) {
      _code.clear();
      controller.dataChanged();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appen är aktiverad.')));
    }
    final s = await controller.repo.licenseState();
    if (mounted) {
      setState(() {
        _busy = false;
        _error = error;
        _state = s;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final license = s?.license;
    return Scaffold(
      appBar: AppBar(title: const Text('Aktivering')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (s != null) Text(licenseStatusText(s), style: Theme.of(context).textTheme.titleMedium),
          if (license != null && license.locksCompany) ...[
            const SizedBox(height: 4),
            Text('${license.companyName}, org.nr ${license.orgNumber}'),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Aktiveringskod', hintText: 'Klistra in koden här'),
            onChanged: (_) => setState(() => _error = null),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: AppTheme.warning)),
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _activate, child: const Text('Aktivera')),
        ],
      ),
    );
  }
}
