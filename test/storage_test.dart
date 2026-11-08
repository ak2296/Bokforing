import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:bokforing/data/storage.dart';
import 'package:bokforing/export/backup.dart';
import 'package:cryptography/cryptography.dart';
import 'package:bokforing/imaging/preprocess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  backupFormatTests();

  test('A saved photo copy is at most 1600 pixels and smaller', () {
    final page = img.Image(width: 2400, height: 3200);
    img.fill(page, color: img.ColorRgb8(245, 245, 240));
    for (var y = 100; y < 3100; y += 60) {
      img.drawLine(page, x1: 120, y1: y, x2: 2200, y2: y, color: img.ColorRgb8(20, 20, 20), thickness: 4);
    }
    final original = img.encodeJpg(page, quality: 92);
    final small = compactJpeg(original);
    final decoded = img.decodeJpg(small)!;
    expect(decoded.height, 1600);
    expect(decoded.width, 1200);
    expect(small.length, lessThan(original.length));
  });

  test('Sizes are shown in kB and MB', () {
    expect(AppStorage.format(512 * 1024), '512 kB');
    expect(AppStorage.format(5 * 1024 * 1024 + 300 * 1024), '5,3 MB');
    expect(AppStorage.format(119 * 1024 * 1024), '119 MB');
  });
}

void backupFormatTests() {
  final sample = {
    'format': Backup.format,
    'version': Backup.version,
    'created': '2026-11-08T10:00:00',
    'tables': {
      'invoices': [for (var i = 0; i < 200; i++) {'id': i, 'supplier': 'Snabbgross', 'total_ore': 125000 + i}],
    },
  };

  test('A backup is packed before it is encrypted, and opens again', () async {
    final bytes = await Backup.encrypt(sample, 'hemligt-lösenord');
    final plain = utf8.encode(jsonEncode(sample)).length;
    // Base64 adds a third, packing removes far more.
    expect(bytes.length, lessThan(plain));
    final back = await Backup.decrypt(bytes, 'hemligt-lösenord');
    expect((back['tables'] as Map)['invoices'], hasLength(200));
  });

  test('A backup inside a ZIP file can be imported', () async {
    final bytes = await Backup.encrypt(sample, 'hemligt-lösenord');
    for (final level in [0, 6]) {
      final zip = ZipEncoder().encode(Archive()..addFile(ArchiveFile('mapp/quee_2026-11-08.bkp', bytes.length, bytes)
        ..compression = level == 0 ? CompressionType.none : CompressionType.deflate));
      final back = await Backup.decrypt(zip, 'hemligt-lösenord');
      expect((back['tables'] as Map)['invoices'], hasLength(200));
    }
  });

  test('An old, unpacked backup (version 1) still opens', () async {
    final salt = List<int>.filled(16, 7);
    final key = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 1000, bits: 256)
        .deriveKeyFromPassword(password: 'hemligt-lösenord', nonce: salt);
    final box = await AesGcm.with256bits().encrypt(utf8.encode(jsonEncode(sample)), secretKey: key);
    final old = utf8.encode(jsonEncode({
      'format': Backup.format,
      'version': 1,
      'kdf': {'name': 'PBKDF2-HMAC-SHA256', 'iterations': 1000, 'salt': base64Encode(salt)},
      'cipher': 'AES-256-GCM',
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'data': base64Encode(box.cipherText),
    }));
    final back = await Backup.decrypt(old, 'hemligt-lösenord');
    expect((back['tables'] as Map)['invoices'], hasLength(200));
  });
}
