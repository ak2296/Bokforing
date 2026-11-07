import 'dart:convert';
import 'dart:io' show GZipCodec, ZLibDecoder;
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

import '../data/database.dart';

/// A key derived from the backup password, with its salt.
class BackupKey {
  final SecretKey key;
  final List<int> salt;
  final int iterations;
  const BackupKey(this.key, this.salt, this.iterations);

  static Future<BackupKey> derive(String password) async {
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    const iterations = Backup._iterations;
    // A few seconds of work by design; kept off the screen's thread.
    final bytes = await Isolate.run(() async => (await Backup._key(password, salt, iterations)).extractBytes());
    return BackupKey(SecretKey(bytes), salt, iterations);
  }
}

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
  /// 2: the content is gzip-compressed before it is encrypted.
  static const version = 2;
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
    'supplier_payment_kinds',
    'online_sales',
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

  static Future<Uint8List> encrypt(Map<String, dynamic> backup, String password) async =>
      encryptWith(backup, await BackupKey.derive(password));

  /// Encrypts with a key derived earlier, so automatic backups need not
  /// derive it again each time (it takes a few seconds by design).
  static Future<Uint8List> encryptWith(Map<String, dynamic> backup, BackupKey key) async {
    final packed = GZipCodec(level: 9).encode(utf8.encode(jsonEncode(backup)));
    final box = await AesGcm.with256bits().encrypt(packed, secretKey: key.key);
    final envelope = {
      'format': format,
      'version': version,
      'compression': 'gzip',
      'kdf': {'name': 'PBKDF2-HMAC-SHA256', 'iterations': key.iterations, 'salt': base64Encode(key.salt)},
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
      env = jsonDecode(utf8.decode(unwrap(bytes))) as Map<String, dynamic>;
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
    if (env['compression'] == 'gzip') clear = GZipCodec().decode(clear);
    final backup = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    if (backup['format'] != format || backup['tables'] is! Map) {
      throw const BackupException('Säkerhetskopian är ofullständig.');
    }
    return backup;
  }

  /// The backup file itself, also when it was put in a ZIP file: the first
  /// ".bkp" in it (or its only file). Anything else is returned unchanged.
  static List<int> unwrap(List<int> bytes) {
    if (bytes.length < 22 || bytes[0] != 0x50 || bytes[1] != 0x4B || bytes[2] != 0x03 || bytes[3] != 0x04) return bytes;
    int u16(int at) => bytes[at] | bytes[at + 1] << 8;
    int u32(int at) => u16(at) | u16(at + 2) << 16;
    // End of central directory, searched from the end.
    var end = -1;
    for (var i = bytes.length - 22; i >= 0 && i >= bytes.length - 22 - 65535; i--) {
      if (u32(i) == 0x06054b50) {
        end = i;
        break;
      }
    }
    if (end < 0) throw const BackupException('ZIP-filen är skadad.');
    final count = u16(end + 10);
    var at = u32(end + 16);
    final entries = <(String, int, int, int)>[];
    for (var n = 0; n < count && u32(at) == 0x02014b50; n++) {
      final method = u16(at + 10), size = u32(at + 20), nameLen = u16(at + 28);
      final extra = u16(at + 30), comment = u16(at + 32), local = u32(at + 42);
      final name = utf8.decode(bytes.sublist(at + 46, at + 46 + nameLen), allowMalformed: true);
      if (!name.endsWith('/')) entries.add((name, method, size, local));
      at += 46 + nameLen + extra + comment;
    }
    final pick = entries.where((e) => e.$1.toLowerCase().endsWith('.bkp')).firstOrNull ??
        (entries.length == 1 ? entries.single : null);
    if (pick == null) throw const BackupException('ZIP-filen innehåller ingen säkerhetskopia (.bkp).');
    final (_, method, size, local) = pick;
    final start = local + 30 + u16(local + 26) + u16(local + 28);
    final data = bytes.sublist(start, start + size);
    return switch (method) {
      0 => data,
      8 => ZLibDecoder(raw: true).convert(data),
      _ => throw const BackupException('ZIP-filen är packad på ett sätt som inte stöds.'),
    };
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
