import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../domain/dates.dart';
import '../../export/backup.dart';
import '../widgets/common.dart';

/// "Exportera säkerhetskopia" / "Importera säkerhetskopia". The file is
/// encrypted with a password the user chooses and saved where the user
/// chooses. Nothing is uploaded automatically.
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;

  Future<String?> _askPassword({required bool confirm}) async {
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    String? error;
    return showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text(confirm ? 'Välj lösenord för säkerhetskopian' : 'Lösenord för säkerhetskopian'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (confirm)
                const Text('Utan lösenordet går säkerhetskopian inte att öppna. Skriv upp det på ett säkert ställe.'),
              TextField(controller: p1, obscureText: true, decoration: const InputDecoration(labelText: 'Lösenord')),
              if (confirm)
                TextField(controller: p2, obscureText: true, decoration: const InputDecoration(labelText: 'Upprepa lösenord')),
              if (error != null) Text(error!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Avbryt')),
            FilledButton(
              onPressed: () {
                if (p1.text.length < 8) {
                  setState(() => error = 'Minst 8 tecken.');
                } else if (confirm && p1.text != p2.text) {
                  setState(() => error = 'Lösenorden är inte lika.');
                } else {
                  Navigator.pop(c, p1.text);
                }
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export() async {
    final controller = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final password = await _askPassword(confirm: true);
    if (password == null) return;
    setState(() => _busy = true);
    try {
      final data = await Backup.collect(controller.repo.db);
      final bytes = await Backup.encrypt(data, password);
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Spara säkerhetskopia',
        fileName: 'bokforing_sakerhetskopia_${SwedishDates.iso(DateTime.now())}.bkp',
        bytes: bytes,
      );
      if (uri != null) {
        await controller.repo.setSetting('last_backup', DateTime.now().toIso8601String());
        messenger.showSnackBar(const SnackBar(content: Text('Säkerhetskopian har sparats.')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Säkerhetskopian kunde inte sparas: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final controller = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty || !mounted) return;
    final password = await _askPassword(confirm: false);
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await files.first.readAsBytes();
      final backup = await Backup.decrypt(bytes, password);
      if (!mounted) return;
      final ok = await confirmDialog(context,
          title: 'Ersätta all data?',
          message: '${Backup.summary(backup)}\n\nAll data som finns i appen nu ersätts med säkerhetskopian. '
              'Exportera gärna en säkerhetskopia av nuvarande data först.',
          confirm: 'Ersätt');
      if (!ok) return;
      await Backup.restore(controller.repo.db, backup);
      controller.dataChanged();
      messenger.showSnackBar(const SnackBar(content: Text('Säkerhetskopian har återställts.')));
    } on BackupException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Säkerhetskopian kunde inte läsas: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Säkerhetskopiering')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Allt sparas bara i telefonen. Om telefonen går sönder eller appen tas bort försvinner uppgifterna. '
              'Spara därför en säkerhetskopia regelbundet, t.ex. varje månad, på ett ställe utanför telefonen '
              '(USB-minne, dator eller din egen molnlagring).',
            ),
            const SizedBox(height: 8),
            const Text('Säkerhetskopian är krypterad med ditt lösenord. Bilder och API-nyckel följer inte med.'),
            const SizedBox(height: 20),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.save_alt),
              label: const Text('Exportera säkerhetskopia'),
              onPressed: _busy ? null : _export,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.restore),
              label: const Text('Importera säkerhetskopia'),
              onPressed: _busy ? null : _import,
            ),
          ],
        ),
      );
}
