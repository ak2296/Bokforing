import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_icons.dart';

import '../../app/app_controller.dart';
import '../../domain/dates.dart';
import '../../export/auto_backup.dart';
import '../../export/backup.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Automatic backup to a folder the user picked, a copy through the share
/// menu, and manual export and import. Every file is encrypted with the
/// user's password. Nothing is uploaded by the app itself.
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;

  /// Folder name, last backup, error; null while loading.
  ({bool active, String? folder, String name, DateTime? last, String? error})? _auto;

  AutoBackup _service(BuildContext context) {
    final c = AppScope.read(context);
    return c.autoBackup ?? AutoBackup(c.repo);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_auto == null) _loadAuto();
  }

  Future<void> _loadAuto() async {
    final a = _service(context);
    final state = (
      active: await a.active(),
      folder: await a.folder(),
      name: await a.folderName(),
      last: await a.last(),
      error: await a.lastError(),
    );
    if (mounted) setState(() => _auto = state);
  }

  Future<void> _turnOn() async {
    final a = _service(context);
    final messenger = ScaffoldMessenger.of(context);
    final dir = await a.pickFolder();
    if (dir == null || !mounted) return;
    final password = await _askPassword(confirm: true);
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await a.turnOn(dir.uri, dir.name, password);
      await a.runNow();
      messenger.showSnackBar(SnackBar(content: Text('Automatisk säkerhetskopia är på. Första kopian finns i ${dir.name}.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Det gick inte att spara i mappen: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
      await _loadAuto();
    }
  }

  Future<void> _runNow() async {
    final messenger = ScaffoldMessenger.of(context);
    final a = _service(context);
    setState(() => _busy = true);
    try {
      final name = await a.runNow();
      messenger.showSnackBar(SnackBar(content: Text('Sparad som $name.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Det gick inte att spara: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
      await _loadAuto();
    }
  }

  Future<void> _turnOff() async {
    final a = _service(context);
    final ok = await confirmDialog(context,
        title: 'Stänga av automatisk säkerhetskopia?',
        message: 'Kopiorna som redan finns i mappen ligger kvar. Appen sparar inga nya.',
        confirm: 'Stäng av');
    if (!ok) return;
    await a.turnOff();
    await _loadAuto();
  }

  Future<void> _share() async {
    final a = _service(context);
    final messenger = ScaffoldMessenger.of(context);
    String? password;
    if (!(_auto?.active ?? false)) {
      password = await _askPassword(confirm: true);
      if (password == null || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await a.share(password: password);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Kopian kunde inte skapas: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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

  Widget _autoCard() {
    final t = Theme.of(context).textTheme;
    final a = _auto;
    if (a == null) return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
    final lost = !a.active && a.folder != null;
    String when(DateTime d) {
      final local = d.toLocal();
      return '${SwedishDates.iso(local)} kl. ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            IconTile(a.active ? AppIcons.checkCircle : AppIcons.backup,
                background: a.active ? AppTheme.tint : AppTheme.hairline, color: a.active ? AppTheme.seed : AppTheme.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Automatisk säkerhetskopia', style: t.titleSmall),
                Text(a.active ? 'På · mapp: ${a.name}' : (lost ? 'Mappen behöver väljas igen' : 'Av'), style: t.bodySmall),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          if (a.active) ...[
            Text(a.last == null ? 'Ingen kopia sparad ännu.' : 'Senaste kopian: ${when(a.last!)}', style: t.bodyMedium),
            if (a.error != null) ...[
              const SizedBox(height: 6),
              Text('Senaste försöket misslyckades: ${a.error}', style: t.bodySmall?.copyWith(color: AppTheme.warning)),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  icon: const Icon(AppIcons.save, size: 18),
                  label: const Text('Spara nu'),
                  onPressed: _busy ? null : _runNow,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(AppIcons.files, size: 18),
                  label: const Text('Byt mapp'),
                  onPressed: _busy ? null : _turnOn,
                ),
              ),
            ]),
            TextButton(onPressed: _busy ? null : _turnOff, child: const Text('Stäng av')),
          ] else ...[
            Text(
              lost
                  ? 'Appen får inte längre spara i den valda mappen, t.ex. efter en återställning. Välj mappen igen.'
                  : 'Appen sparar en krypterad kopia i en mapp du väljer, efter varje ändring (högst en fil per dag). '
                      'De $keepText senaste behålls. Kopiorna finns kvar även om appens data rensas eller appen tas bort.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(AppIcons.files),
              label: Text(lost ? 'Välj mappen igen' : 'Välj mapp och slå på'),
              onPressed: _busy ? null : _turnOn,
            ),
          ],
        ]),
      ),
    );
  }

  static const keepText = '${AutoBackup.keep}';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Säkerhetskopiering')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _autoCard(),
          const SizedBox(height: 8),
          Text(
            'Välj gärna en mapp under Dokument, t.ex. Dokument/Bokföring. Ligger mappen på telefonen försvinner den '
            'med telefonen, så skicka ibland en kopia till molnet också.',
            style: t.bodySmall,
          ),
          const SizedBox(height: 20),
          if (_busy) ...[const LinearProgressIndicator(), const SizedBox(height: 8)],
          Text('Kopia till molnet', style: t.titleSmall),
          const SizedBox(height: 4),
          Text('Skicka en kopia till Google Drive, OneDrive, Box eller e-post via telefonens delningsmeny.',
              style: t.bodySmall),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(AppIcons.cloudUpload),
            label: const Text('Skicka kopia'),
            onPressed: _busy ? null : _share,
          ),
          const SizedBox(height: 20),
          Text('Spara eller återställ själv', style: t.titleSmall),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(AppIcons.save),
            label: const Text('Exportera säkerhetskopia'),
            onPressed: _busy ? null : _export,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(AppIcons.restore),
            label: const Text('Importera säkerhetskopia'),
            onPressed: _busy ? null : _import,
          ),
          const SizedBox(height: 12),
          Text(
            'Kopiorna är krypterade med ditt lösenord och packade, så de tar lite plats. Bilder och API-nyckel följer '
            'inte med. Vid import går det bra med både .bkp-filen och en ZIP-fil som innehåller den. Utan lösenordet '
            'går en kopia inte att öppna.',
            style: t.bodySmall,
          ),
        ],
      ),
    );
  }
}
