import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../imaging/preprocess.dart';
import 'database.dart';

/// How much space the app uses on the phone, in bytes.
class StorageUsage {
  final int database;
  final int images;
  final int imageCount;
  final int temp;

  /// Everything else in the app's folders: the app's own working files, and
  /// in a test (debug) version its developer code.
  final int other;
  const StorageUsage(this.database, this.images, this.imageCount, this.temp, {this.other = 0});
  int get total => database + images + temp + other;
}

/// Space on the phone: what the app uses and how to free it. Nothing here
/// touches the bookkeeping figures.
class AppStorage {
  const AppStorage._();

  static const _scanFiles = ['.jpg', '.jpeg', '.png', '.pdf', '.bkp'];

  static Future<Directory> imagesDir() async =>
      Directory(p.join((await getApplicationDocumentsDirectory()).path, 'skanningar'));

  static Future<int> _size(Directory dir, {bool Function(File)? where}) async {
    if (!await dir.exists()) return 0;
    var n = 0;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File && (where == null || where(e))) {
          try {
            n += await e.length();
          } on FileSystemException {
            // Gone while counting.
          }
        }
      }
    } on FileSystemException {
      // A folder the app may not read; count what was reached.
    }
    return n;
  }

  static bool _isScanFile(File f) => _scanFiles.contains(p.extension(f.path).toLowerCase());

  static Future<StorageUsage> usage() async {
    final dbPath = p.join(await getDatabasesPath(), AppDatabase.fileName);
    var db = 0;
    for (final suffix in ['', '-wal', '-journal', '-shm']) {
      final f = File('$dbPath$suffix');
      if (await f.exists()) db += await f.length();
    }
    final images = await imagesDir();
    var count = 0;
    if (await images.exists()) {
      count = await images.list().where((e) => e is File).length;
    }
    final tempDir = await getTemporaryDirectory();
    final temp = await _size(tempDir, where: _isScanFile);
    final imageBytes = await _size(images);
    // The app's whole data folder, less what is counted above.
    var all = 0;
    try {
      final docs = await getApplicationDocumentsDirectory();
      all = await _size(docs.parent);
      if (!p.isWithin(docs.parent.path, tempDir.path)) all += await _size(tempDir);
      if (!p.isWithin(docs.parent.path, dbPath)) all += db;
    } catch (_) {
      all = 0;
    }
    final other = all - db - imageBytes - temp;
    return StorageUsage(db, imageBytes, count, temp, other: other > 0 ? other : 0);
  }

  /// Deletes photos and PDF pages left in the cache by scans that were
  /// closed without saving. [olderThan] spares a scan in progress.
  static Future<int> cleanTemp({Duration olderThan = const Duration(minutes: 30)}) async {
    var freed = 0;
    try {
      final dir = await getTemporaryDirectory();
      final limit = DateTime.now().subtract(olderThan);
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is! File || !_isScanFile(e)) continue;
        try {
          final stat = await e.stat();
          if (stat.modified.isAfter(limit)) continue;
          await e.delete();
          freed += stat.size;
        } on FileSystemException {
          // In use or already gone.
        }
      }
    } catch (_) {
      // Cleaning is a help, never a reason to fail.
    }
    return freed;
  }

  /// Saves kept photos again in the smaller format. A photo is replaced only
  /// when the new copy is smaller and could be written in full.
  static Future<int> compactImages({void Function(int done, int total)? progress}) async {
    final dir = await imagesDir();
    if (!await dir.exists()) return 0;
    final files = await dir.list().where((e) => e is File).cast<File>().where(_isScanFile).toList();
    var saved = 0;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      try {
        final before = await f.readAsBytes();
        final after = await compute(compactJpeg, before);
        if (after.length < before.length * 0.9) {
          final tmp = File('${f.path}.tmp');
          await tmp.writeAsBytes(after, flush: true);
          if (await tmp.length() == after.length) {
            await tmp.rename(f.path);
            saved += before.length - after.length;
          } else {
            await tmp.delete();
          }
        }
      } catch (_) {
        // Leave this photo as it is.
      }
      progress?.call(i + 1, files.length);
    }
    return saved;
  }

  /// Deletes every kept photo and the links to them. The registrations and
  /// their read text stay; only the pictures go.
  static Future<int> deleteImages(Database db) async {
    final dir = await imagesDir();
    final size = await _size(dir);
    if (await dir.exists()) await dir.delete(recursive: true);
    await db.update('document_scans', {'image_path': null});
    return size;
  }

  /// Gives space freed inside the database back to the phone.
  static Future<void> shrinkDatabase(Database db) => db.execute('VACUUM');

  /// "12,3 MB".
  static String format(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} kB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0).replaceAll('.', ',')} MB';
  }
}
