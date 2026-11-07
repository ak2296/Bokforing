import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../data/storage.dart';
import '../app_icons.dart';
import '../theme.dart';

/// "Lagring": how much space the app takes and a button to free some. The
/// bookkeeping figures are never touched.
class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  StorageUsage? _usage;
  bool _working = false;
  String? _progress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final u = await AppStorage.usage();
    if (mounted) setState(() => _usage = u);
  }

  Future<void> _free() async {
    final db = AppScope.read(context).repo.db;
    final messenger = ScaffoldMessenger.of(context);
    final before = _usage?.total ?? 0;
    setState(() {
      _working = true;
      _progress = 'Rensar tillfälliga filer…';
    });
    await AppStorage.cleanTemp(olderThan: Duration.zero);
    await AppStorage.compactImages(progress: (done, total) {
      if (mounted) setState(() => _progress = 'Gör sparade bilder mindre: $done av $total');
    });
    if (mounted) setState(() => _progress = 'Packar databasen…');
    await AppStorage.shrinkDatabase(db);
    final after = await AppStorage.usage();
    if (!mounted) return;
    setState(() {
      _usage = after;
      _working = false;
      _progress = null;
    });
    final freed = before - after.total;
    messenger.showSnackBar(SnackBar(
        content: Text(freed > 0 ? '${AppStorage.format(freed)} frigjort.' : 'Det fanns inget mer att frigöra.')));
  }

  @override
  Widget build(BuildContext context) {
    final u = _usage;
    final t = Theme.of(context).textTheme;
    Widget row(IconData icon, String label, String sub, int bytes) => ListTile(
          leading: IconTile(icon),
          title: Text(label),
          subtitle: Text(sub),
          trailing: Text(AppStorage.format(bytes), style: t.titleSmall?.merge(moneyStyle)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Lagring')),
      body: u == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(children: [
                      row(AppIcons.backup, 'Bokföringsuppgifter', 'Alla belopp, datum och texter', u.database),
                      const Divider(indent: 70),
                      row(AppIcons.image, 'Sparade bilder', '${u.imageCount} bilder', u.images),
                      const Divider(indent: 70),
                      row(AppIcons.files, 'Tillfälliga filer', 'Bilder från avbrutna skanningar', u.temp),
                      const Divider(indent: 70),
                      ListTile(
                        title: Text('Totalt', style: t.titleSmall),
                        trailing: Text(AppStorage.format(u.total), style: t.titleMedium?.merge(moneyStyle)),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: _working
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(AppIcons.restore),
                  label: Text(_working ? (_progress ?? 'Arbetar…') : 'Frigör utrymme'),
                  onPressed: _working ? null : _free,
                ),
                const SizedBox(height: 12),
                Text(
                  'Tar bort tillfälliga filer, gör sparade bilder mindre (texten går fortfarande att läsa) och packar '
                  'databasen. Inga belopp, datum eller registreringar tas bort.',
                  style: t.bodySmall,
                ),
              ],
            ),
    );
  }
}
