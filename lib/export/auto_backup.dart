import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:share_plus/share_plus.dart';

import '../data/repository.dart';
import '../domain/dates.dart';
import 'backup.dart';

/// Encrypted backups written by themselves to a folder the user picked once,
/// such as Dokument/Quee on the phone. One file per day (the day's file
/// is replaced as data changes); the [keep] newest are kept. The files stay
/// when the app's data is cleared or the app is removed.
class AutoBackup {
  static const folderKey = 'auto_backup_folder';
  static const folderNameKey = 'auto_backup_folder_name';
  static const lastKey = 'auto_backup_last';
  static const errorKey = 'auto_backup_error';

  /// Set when data changed and the backup has not been written yet.
  static const pendingKey = 'auto_backup_pending';
  static const _passwordKey = 'auto_backup_password';
  static const keep = 3;
  static const _storage = FlutterSecureStorage();
  // Files from before the app was named Quee start with "bokforing_".
  static final _name = RegExp(r'^(quee|bokforing)_\d{4}-\d{2}-\d{2}\.bkp$');

  final Repository repo;
  AutoBackup(this.repo);

  final _saf = SafUtil();
  final _stream = SafStream();
  BackupKey? _key;
  Timer? _timer;
  Future<void>? _running;

  static String fileName(DateTime day) => 'quee_${SwedishDates.iso(day)}.bkp';

  Future<String?> folder() async {
    final f = await repo.setting(folderKey);
    return f == null || f.isEmpty ? null : f;
  }

  Future<String> folderName() async => await repo.setting(folderNameKey) ?? '';
  Future<DateTime?> last() async => DateTime.tryParse(await repo.setting(lastKey) ?? '');
  Future<String?> lastError() async {
    final e = await repo.setting(errorKey);
    return e == null || e.isEmpty ? null : e;
  }

  /// True when a folder is chosen and the app may still write to it. After
  /// "Clear data" or a restore on a new phone the permission is gone.
  Future<bool> active() async {
    final f = await folder();
    if (f == null) return false;
    try {
      return await _saf.hasPersistedPermission(f, checkRead: true, checkWrite: true) &&
          await _storage.read(key: _passwordKey) != null;
    } catch (_) {
      return false;
    }
  }

  /// Lets the user pick the folder; null when cancelled.
  Future<({String uri, String name})?> pickFolder() async {
    final dir = await _saf.pickDirectory(writePermission: true, persistablePermission: true);
    return dir == null ? null : (uri: dir.uri, name: dir.name);
  }

  Future<void> turnOn(String uri, String name, String password) async {
    await _storage.write(key: _passwordKey, value: password);
    _key = null;
    final old = await folder();
    if (old != null && old != uri) await _release(old);
    await repo.setSetting(folderKey, uri);
    await repo.setSetting(folderNameKey, name);
    await repo.setSetting(errorKey, '');
  }

  Future<void> turnOff() async {
    _timer?.cancel();
    final f = await folder();
    if (f != null) await _release(f);
    await _storage.delete(key: _passwordKey);
    _key = null;
    await repo.setSetting(folderKey, '');
    await repo.setSetting(folderNameKey, '');
    await repo.setSetting(errorKey, '');
  }

  Future<void> _release(String uri) async {
    try {
      await _saf.releasePersistedPermission(uri, read: true, write: true);
    } catch (_) {
      // Already gone.
    }
  }

  /// Called after every saved change: the backup runs a little later, so a
  /// series of saves gives one write.
  void schedule() {
    repo.setSetting(pendingKey, '1');
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 20), () => runQuietly());
  }

  /// Runs the backup if it is on; a failure is remembered for the settings
  /// page instead of interrupting the user.
  Future<void> runQuietly({bool onlyIfPending = false}) async {
    try {
      if (onlyIfPending && await repo.setting(pendingKey) != '1') return;
      if (await active()) await runNow();
    } catch (e) {
      await repo.setSetting(errorKey, '$e');
    }
  }

  /// Writes today's backup and removes the oldest beyond [keep]. Returns the
  /// file name.
  Future<String> runNow() async {
    while (_running != null) {
      await _running;
    }
    final done = Completer<void>();
    _running = done.future;
    try {
      final f = await folder();
      if (f == null) throw const BackupException('Ingen mapp är vald.');
      final bytes = await Backup.encryptWith(await Backup.collect(repo.db), await _derivedKey());
      final name = fileName(DateTime.now());
      await _stream.writeFileBytes(f, name, 'application/octet-stream', bytes, overwrite: true);
      await _prune(f);
      await repo.setSetting(lastKey, DateTime.now().toIso8601String());
      await repo.setSetting(errorKey, '');
      await repo.setSetting(pendingKey, '');
      return name;
    } finally {
      _running = null;
      done.complete();
    }
  }

  Future<BackupKey> _derivedKey() async {
    final cached = _key;
    if (cached != null) return cached;
    final password = await _storage.read(key: _passwordKey);
    if (password == null) throw const BackupException('Lösenordet för automatisk säkerhetskopia saknas. Slå på den igen.');
    return _key = await BackupKey.derive(password);
  }

  /// Only the app's own backup files are ever deleted, never anything else
  /// in the folder.
  Future<void> _prune(String folder) async {
    final files = (await _saf.list(folder)).where((d) => !d.isDir && _name.hasMatch(d.name)).toList()
      ..sort((a, b) => b.name.compareTo(a.name));
    for (final old in files.skip(keep)) {
      try {
        await _saf.delete(old.uri, false);
      } catch (_) {
        // Try again next time.
      }
    }
  }

  /// A fresh backup offered to Google Drive, OneDrive, Box or any other app
  /// through Android's share menu. [password] is needed when automatic
  /// backup is off.
  Future<void> share({String? password}) async {
    final key = password != null ? await BackupKey.derive(password) : await _derivedKey();
    final bytes = await Backup.encryptWith(await Backup.collect(repo.db), key);
    final tmp = File(p.join((await getTemporaryDirectory()).path, fileName(DateTime.now())));
    await tmp.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(tmp.path, mimeType: 'application/octet-stream')],
      subject: 'Säkerhetskopia Quee ${SwedishDates.iso(DateTime.now())}',
    ));
  }
}
