import 'package:flutter/material.dart';

import '../app_icons.dart';

import '../../ai/gemini_client.dart';
import '../../app/app_controller.dart';

/// Optional online analysis with the owner's own Gemini API key.
class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  bool _loaded = false;
  bool _enabled = false;
  bool _hasKey = false;
  bool _showKey = false;
  final _key = TextEditingController();
  final _model = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      AiSettings.load(AppScope.read(context).repo).then((s) {
        if (!mounted) return;
        setState(() {
          _enabled = s.enabled;
          _hasKey = (s.apiKey ?? '').isNotEmpty;
          _model.text = s.model;
        });
      });
    }
  }

  Future<void> _save() async {
    final repo = AppScope.read(context).repo;
    if (_key.text.trim().isNotEmpty) {
      await AiSettings.saveKey(_key.text);
      _hasKey = true;
      _key.clear();
    }
    final model = _model.text.trim().isEmpty ? AiSettings.defaultModel : _model.text.trim();
    await repo.setSetting(AiSettings.modelKey, model);
    await repo.setBoolSetting(AiSettings.enabledKey, _enabled && _hasKey);
    if (!mounted) return;
    setState(() => _enabled = _enabled && _hasKey);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Inställningarna har sparats.')));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Förbättrad analys')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Valfritt. När telefonen inte kan läsa ett dokument säkert kan du välja att skicka bilden till '
            'Googles AI-tjänst Gemini för tolkning. Appen frågar varje gång innan något skickas, och svaret '
            'kontrolleras och godkänns av dig precis som vanligt.',
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bra att veta', style: t.titleSmall),
                  const SizedBox(height: 6),
                  const Text('• Kräver internet. Grundfunktionerna fungerar alltid utan internet.'),
                  const Text('• Med den kostnadsfria nivån kan Google använda innehållet för att förbättra sina '
                      'tjänster och låta människor granska det. Läs Googles villkor för Gemini API.'),
                  const Text('• Gratiskvoten bestäms av Google och syns i ditt konto på aistudio.google.com. '
                      'Den kan ändras och är inte garanterad.'),
                  const Text('• Nyckeln sparas krypterat i telefonen och följer inte med i säkerhetskopior.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Aktivera förbättrad analys'),
            subtitle: Text(_hasKey ? 'API-nyckel finns sparad' : 'Klistra in en API-nyckel först'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _key,
            obscureText: !_showKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: _hasKey ? 'Ny API-nyckel (lämna tomt för att behålla)' : 'API-nyckel från Google AI Studio',
              helperText: 'Skapa en nyckel på aistudio.google.com under "Get API key".',
              suffixIcon: IconButton(
                tooltip: _showKey ? 'Dölj' : 'Visa',
                icon: Icon(_showKey ? AppIcons.visibilityOff : AppIcons.visibility),
                onPressed: () => setState(() => _showKey = !_showKey),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _model,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Modell',
              helperText: 'Standard: ${AiSettings.defaultModel}. Ändra bara om Google byter namn på modellen.',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: (_enabled && !_hasKey && _key.text.trim().isEmpty) ? null : _save,
            child: const Text('Spara'),
          ),
          if (_hasKey) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                final repo = AppScope.read(context).repo;
                await AiSettings.saveKey(null);
                await repo.setBoolSetting(AiSettings.enabledKey, false);
                if (!mounted) return;
                setState(() {
                  _hasKey = false;
                  _enabled = false;
                });
              },
              child: const Text('Ta bort API-nyckeln'),
            ),
          ],
        ],
      ),
    );
  }
}
