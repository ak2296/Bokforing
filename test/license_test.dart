import 'dart:convert';

import 'package:bokforing/data/database.dart';
import 'package:bokforing/data/repository.dart';
import 'package:bokforing/app/settings_keys.dart';
import 'package:bokforing/domain/license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Signed with the published RFC 8032 test key, never with the owner's.
final _testKey = base64Url
    .encode([
      0xd7, 0x5a, 0x98, 0x01, 0x82, 0xb1, 0x0a, 0xb7, 0xd5, 0x4b, 0xfe, 0xd3, 0xc9, 0x64, 0x07, 0x3a,
      0x0e, 0xe1, 0x72, 0xf3, 0xda, 0xa6, 0x23, 0x25, 0xaf, 0x02, 0x1a, 0x68, 0xf7, 0x07, 0x51, 0x1a,
    ])
    .replaceAll('=', '');
const _customer =
    'BOK1.QzF8RXhlbXBlbCBBQnw1NTYwMDAtMDAwMHwyMDMwLTA2LTMw.dAfuPz-FoqJivZq4hzYiLKoSLFXILS82CH1qvOKSU3lwS1aaQCAA4puykDe_V_WeOI23Mip-aGTw67FQptY5BA';
const _noEnd =
    'BOK1.dGVzdC0xfHx8._3I1GjUaz1eme1Z_ENKtXVb_DwGnZlySl96xHfglvquXe03JoNY1JuO-LjYdwZ4LyuuRs3HjTGKOZ7LN6jobCQ';

/// Signed with the app's real key, but it ended in 2020 so it opens nothing.
const _realExpired =
    'BOK1.ZXhwaXJlZC1zYW1wbGV8RXhlbXBlbCBBQnw1NTYwMDAtMDAwMHwyMDIwLTAxLTMx.LIsj36uUhSjT0v1OUQCOa2DH2jBPJoA3Swzlr2eFSAuUqf0T6bEaMTcF6SSok5VjZKC6Gm2XYJAnQHhNhBFNDw';

void main() {
  final checker = LicenseChecker(publicKey: _testKey, revoked: const {});

  test('a customer code carries company and end date, and works up to that day', () async {
    final l = await checker.read(_customer);
    expect(l!.companyName, 'Exempel AB');
    expect(l.orgNumber, '556000-0000');
    expect(l.until, '2030-06-30');
    expect(l.locksCompany, isTrue);
    expect(checker.statusOf(l, '2030-06-30'), LicenseStatus.active);
    expect(checker.statusOf(l, '2030-07-01'), LicenseStatus.expired);
  });

  test('a test code has no end date and locks no company', () async {
    final l = await checker.read(_noEnd);
    expect(l!.id, 'test-1');
    expect(l.until, isNull);
    expect(l.locksCompany, isFalse);
    expect(checker.statusOf(l, '2099-12-31'), LicenseStatus.active);
  });

  test('an ended code never works again', () async {
    final ended = LicenseChecker(publicKey: _testKey, revoked: const {'test-1'});
    expect(ended.statusOf(await ended.read(_noEnd), '2026-11-05'), LicenseStatus.revoked);
  });

  test('changed, damaged or foreign codes are refused', () async {
    final parts = _customer.split('.');
    final other = _noEnd.split('.');
    expect(await checker.read('BOK1.${other[1]}.${parts[2]}'), isNull);
    expect(await checker.read('BOK1.${parts[1]}.abcd'), isNull);
    expect(await checker.read('hej'), isNull);
    expect(await checker.read(''), isNull);
    expect(await const LicenseChecker().read(_customer), isNull);
  });

  test("the app's real key checks a real code", () async {
    const real = LicenseChecker();
    final l = await real.read(_realExpired);
    expect(l!.until, '2020-01-31');
    expect(real.statusOf(l, '2026-11-05'), LicenseStatus.expired);
    expect(real.statusOf(null, '2026-11-05'), LicenseStatus.missing);
  });

  group('On the phone', () {
    late Repository repo;
    setUp(() async {
      sqfliteFfiInit();
      repo = Repository(await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
    });
    tearDown(() => repo.db.close());

    test('activating stores the code and fixes the company', () async {
      expect((await repo.licenseState(checker: checker)).status, LicenseStatus.missing);
      expect(await repo.activateLicense(' $_customer\n', checker: checker), isNull);
      expect((await repo.licenseState(checker: checker)).status, LicenseStatus.active);
      final p = await repo.profile();
      expect(p.name, 'Exempel AB');
      expect(p.orgNumber, '556000-0000');
    });

    test('a test code leaves the company as it is', () async {
      expect(await repo.activateLicense(_noEnd, checker: checker), isNull);
      expect((await repo.profile()).name, '');
    });

    test('a refused code changes nothing', () async {
      expect(await repo.activateLicense('hej', checker: checker), contains('stämmer inte'));
      expect(await repo.activateLicense(_realExpired), contains('2020-01-31'));
      expect((await repo.licenseState()).status, LicenseStatus.missing);
    });

    test('setting the clock back does not revive an expired code', () async {
      expect(await repo.activateLicense(_customer, checker: checker), isNull);
      await repo.setSetting(SettingsKeys.licenseLastSeen, '2031-01-01');
      expect((await repo.licenseState(checker: checker)).status, LicenseStatus.expired);
    });
  });
}
