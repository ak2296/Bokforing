import 'package:flutter/material.dart';

import '../../app/activation_service.dart';
import '../../app/app_controller.dart';
import '../../app/pin_lock.dart';
import '../../data/activation_cloud.dart';
import '../../domain/company_pair.dart';
import '../../domain/license.dart';
import '../../domain/models.dart';
import '../theme.dart';
import '../widgets/blur_overlay.dart';

String licenseStatusText(LicenseState s) => switch (s.status) {
      LicenseStatus.active when s.license?.isTrial ?? false => 'Provperiod till ${s.license!.until}',
      LicenseStatus.active => s.license?.until == null
          ? 'Aktiverad, inget slutdatum'
          : 'Aktiverad till ${s.license!.until}',
      LicenseStatus.missing => 'Inte aktiverad',
      LicenseStatus.expired when s.license?.isTrial ?? false => 'Provperioden gick ut ${s.license?.until ?? ''}',
      LicenseStatus.expired => 'Koden gick ut ${s.license?.until ?? ''}',
      LicenseStatus.revoked => 'Koden är avslutad',
      LicenseStatus.mismatch =>
        'Företagsnamn eller organisationsnummer har ändrats. Ändra tillbaka under Inställningar → Företag.',
    };

/// Asks the server whether the owner has sent the code and, when it has come,
/// activates the app. Returns true when the app was just activated.
Future<bool> collectActivation(BuildContext context) async {
  final controller = AppScope.read(context);
  final r = await ActivationService(controller.repo, ActivationCloud(SecureLockStore())).collect();
  if (r.activated) controller.dataChanged();
  return r.activated;
}

/// True when new papers may be saved. Otherwise says why and offers to
/// activate. Viewing, reports, PDF and backup always keep working.
Future<bool> requireLicense(BuildContext context) async {
  final state = await AppScope.read(context).repo.licenseState();
  if (state.status == LicenseStatus.active || !context.mounted) return state.status == LicenseStatus.active;
  final activate = await showBlurDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Appen behöver aktiveras'),
      content: Text('${licenseStatusText(state)}. Du kan fortfarande se allt, skapa rapporter och göra säkerhetskopior, '
          'men inte registrera nya dokument.'),
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
  BusinessProfile _profile = const BusinessProfile();
  ({String id, String name, String org})? _order;
  String _orderStatus = '';
  String? _error;
  String? _orderError;
  bool _busy = false;
  bool _ordering = false;

  ActivationService get _service => ActivationService(AppScope.read(context).repo, ActivationCloud(SecureLockStore()));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_state == null) _load().then((_) => _check(quiet: true));
  }

  Future<void> _load() async {
    final repo = AppScope.read(context).repo;
    final s = await repo.licenseState();
    final p = await repo.profile();
    final o = await repo.order();
    if (mounted) {
      setState(() {
        _state = s;
        _profile = p;
        _order = o;
      });
    }
  }

  Future<void> _placeOrder() async {
    setState(() {
      _ordering = true;
      _orderError = null;
    });
    final error = await _service.placeOrder();
    if (!mounted) return;
    AppScope.read(context).dataChanged();
    await _load();
    if (mounted) {
      setState(() {
        _ordering = false;
        _orderError = error;
      });
    }
  }

  /// Asks the server whether the owner has answered; [quiet] hides "nothing yet".
  Future<void> _check({bool quiet = false}) async {
    if (_order == null) return;
    setState(() => _ordering = true);
    final controller = AppScope.read(context);
    final r = await ActivationService(controller.repo, ActivationCloud(SecureLockStore())).collect();
    if (!mounted) return;
    if (r.activated) {
      controller.dataChanged();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appen är aktiverad.')));
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _ordering = false;
      _orderStatus = r.status;
    });
    if (!quiet) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r.status == 'avslagen' ? 'Beställningen avslogs.' : 'Inget svar än. Du får koden här när den är klar.')));
    }
  }

  Widget _orderCard(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final o = _order;
    final same = o != null && CompanyPair.same(o.name, o.org, _profile.name, _profile.orgNumber);
    if (same) {
      final label = switch (_orderStatus) {
        'betald' => 'Betalningen är registrerad, koden kommer snart',
        'avslagen' => 'Beställningen avslogs',
        _ => 'Väntar på betalning',
      };
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('DIN BESTÄLLNING', style: t.labelMedium?.copyWith(color: AppTheme.muted, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Text(o.name, style: t.titleMedium),
            Text(o.org),
            const SizedBox(height: 8),
            Text(label, style: t.bodyMedium?.copyWith(color: AppTheme.pumpkinText)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _ordering ? null : () => _check(), child: Text(_ordering ? 'Kollar …' : 'Kontrollera nu')),
            const SizedBox(height: 8),
            Text('Appen kollar själv varje gång du öppnar den.', style: t.bodySmall?.copyWith(color: AppTheme.muted)),
          ]),
        ),
      );
    }
    final problem = ActivationService.companyProblem(_profile.name, _profile.orgNumber);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('BESTÄLL AKTIVERING', style: t.labelMedium?.copyWith(color: AppTheme.muted, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Text(_profile.name.isEmpty ? 'Företagsnamn saknas' : _profile.name, style: t.titleMedium),
          Text(_profile.orgNumber.isEmpty ? 'Organisationsnummer saknas' : _profile.orgNumber),
          const SizedBox(height: 12),
          FilledButton(onPressed: problem != null || _ordering ? null : _placeOrder, child: Text(_ordering ? 'Skickar …' : 'Beställ aktivering')),
          const SizedBox(height: 8),
          Text(
            problem ??
                'Du får en veckas provperiod direkt. Namn och nummer kommer från Företag, de står på alla dina rapporter och kan inte ändras efteråt.',
            style: t.bodySmall?.copyWith(color: problem != null ? AppTheme.warning : AppTheme.muted),
          ),
          if (_orderError != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_orderError!, style: TextStyle(color: AppTheme.warning))),
        ]),
      ),
    );
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
      controller.dataChanged();
      // Back to where the owner was: a scan that asked for activation carries on.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appen är aktiverad.')));
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
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
          if (s != null && s.status == LicenseStatus.active && (license?.isTrial ?? false)) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppTheme.tint, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Du har fått en veckas provperiod!',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppTheme.seed, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Appen är aktiv till och med ${license!.until}. Är du betalande kund får du din aktiveringsnyckel här, '
                    'och appen aktiveras av sig själv.'),
              ]),
            ),
          ],
          if (s != null && s.status != LicenseStatus.active || (license?.isTrial ?? false)) ...[
            const SizedBox(height: 12),
            _orderCard(context),
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
              child: Text(_error!, style: TextStyle(color: AppTheme.warning)),
            ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _activate, child: const Text('Aktivera')),
        ],
      ),
    );
  }
}
