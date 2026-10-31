import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database.dart';

class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}

/// Encrypted JSON backup of all accounting data. Monthly and yearly figures
/// are derived from these records, so they come back automatically. Image
/// files and the online-analysis API key are not included.
class Backup {
  const Backup._();

  static const format = 'bokforing-sakerhetskopia';
  static const version = 1;
  static const _iterations = 120000;

  /// Parent tables first; restoring inserts in this order and deletes in
  /// the reverse order.
  static const tables = [
    'business_profile',
    'settings',
    'vat_rates',
    'categories',
    'category_aliases',
    'z_ignored_labels',
    'document_scans',
    'daily_sales',
    'daily_sales_items',
    'invoices',
    'invoice_vat',
    'audit_log',
  ];

  static Future<Map<String, dynamic>> collect(Database db) async {
    final data = <String, dynamic>{};
    for (final t in tables) {
      final rows = await db.query(t);
      data[t] = [
        for (final r in rows)
          if (t == 'document_scans') {...r, 'image_path': null} else r,
      ];
    }
    return {
      'format': format,
      'version': version,
      'schema': AppDatabase.version,
      'created': DateTime.now().toIso8601String(),
      'tables': data,
    };
  }

  static Future<Uint8List> encrypt(Map<String, dynamic> backup, String password) async {
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final key = await _key(password, salt, _iterations);
    final box = await AesGcm.with256bits().encrypt(utf8.encode(jsonEncode(backup)), secretKey: key);
    final envelope = {
      'format': format,
      'version': version,
      'kdf': {'name': 'PBKDF2-HMAC-SHA256', 'iterations': _iterations, 'salt': base64Encode(salt)},
      'cipher': 'AES-256-GCM',
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'data': base64Encode(box.cipherText),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  static Future<Map<String, dynamic>> decrypt(List<int> bytes, String password) async {
    Map<String, dynamic> env;
    try {
      env = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const BackupException('Filen är inte en säkerhetskopia från appen.');
    }
    if (env['format'] != format) throw const BackupException('Filen är inte en säkerhetskopia från appen.');
    if ((env['version'] as int? ?? 0) > version) {
      throw const BackupException('Säkerhetskopian kommer från en nyare version av appen. Uppdatera appen först.');
    }
    final kdf = env['kdf'] as Map<String, dynamic>;
    final key = await _key(password, base64Decode(kdf['salt'] as String), kdf['iterations'] as int);
    final box = SecretBox(
      base64Decode(env['data'] as String),
      nonce: base64Decode(env['nonce'] as String),
      mac: Mac(base64Decode(env['mac'] as String)),
    );
    List<int> clear;
    try {
      clear = await AesGcm.with256bits().decrypt(box, secretKey: key);
    } on SecretBoxAuthenticationError {
      throw const BackupException('Fel lösenord, eller så är filen skadad.');
    }
    final backup = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    if (backup['format'] != format || backup['tables'] is! Map) {
      throw const BackupException('Säkerhetskopian är ofullständig.');
    }
    return backup;
  }

  static Future<SecretKey> _key(String password, List<int> salt, int iterations) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
          .deriveKeyFromPassword(password: password, nonce: salt);

  /// Replaces all data with the backup in one transaction: either everything
  /// is restored or nothing changes.
  static Future<void> restore(Database db, Map<String, dynamic> backup) async {
    final data = backup['tables'] as Map<String, dynamic>;
    await db.transaction((txn) async {
      for (final t in tables.reversed) {
        await txn.delete(t);
      }
      for (final t in tables) {
        for (final row in (data[t] as List? ?? const [])) {
          await txn.insert(t, Map<String, Object?>.from(row as Map));
        }
      }
      await txn.insert('audit_log', {
        'entity': 'backup',
        'entity_id': null,
        'action': 'import',
        'details': 'Säkerhetskopia från ${backup['created']} återställd',
        'at': DateTime.now().toIso8601String(),
      });
    });
  }

  /// Short description shown before the user confirms a restore.
  static String summary(Map<String, dynamic> backup) {
    final t = backup['tables'] as Map<String, dynamic>;
    int n(String table) => (t[table] as List? ?? const []).length;
    final created = DateTime.tryParse('${backup['created']}');
    return 'Skapad: ${created == null ? 'okänt' : created.toLocal().toString().substring(0, 16)}\n'
        'Fakturor: ${n('invoices')}\n'
        'Z-rapporter: ${n('daily_sales')}\n'
        'Kategorier: ${n('categories')}';
  }
}
