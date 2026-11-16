import 'dart:convert';

import 'package:bokforing/app/activation_service.dart';
import 'package:bokforing/app/pin_lock.dart';
import 'package:bokforing/data/activation_cloud.dart';
import 'package:bokforing/data/database.dart';
import 'package:bokforing/data/repository.dart';
import 'package:bokforing/domain/company_pair.dart';
import 'package:bokforing/domain/license.dart';
import 'package:bokforing/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Mem implements LockStore {
  final m = <String, String>{};
  @override
  Future<String?> read(String key) async => m[key];
  @override
  Future<void> write(String key, String value) async => m[key] = value;
  @override
  Future<void> delete(String key) async => m.remove(key);
}

/// A stand-in for the server: records the writes and answers like Firebase.
class _Server {
  bool trialTaken = false;
  String status = 'ny';
  String code = '';
  final writes = <Map<String, dynamic>>[];

  MockClient get client => MockClient((req) async {
        final url = req.url.toString();
        if (url.contains('accounts:signUp')) {
          return http.Response(jsonEncode({'idToken': 't', 'refreshToken': 'r', 'expiresIn': '3600', 'localId': 'u1'}), 200);
        }
        if (url.endsWith(':commit')) {
          final w = (jsonDecode(req.body)['writes'] as List).first as Map<String, dynamic>;
          writes.add(w);
          if ((w['update']['name'] as String).contains('/trials/')) {
            if (trialTaken) return http.Response('{}', 409);
            return http.Response(jsonEncode({'commitTime': '2026-11-16T20:00:00Z'}), 200);
          }
          return http.Response(jsonEncode({'commitTime': '2026-11-16T20:00:00Z'}), 200);
        }
        if (url.contains('/requests/')) {
          return http.Response(
              jsonEncode({
                'fields': {'status': {'stringValue': status}, 'code': {'stringValue': code}}
              }),
              200);
        }
        if (url.contains('/trials/')) return http.Response('{}', 403);
        return http.Response('{}', 404);
      });
}

const _org = '556016-0680';

void main() {
  group('The company pair', () {
    test('capitals, spaces, dots and hyphens do not matter', () {
      expect(CompanyPair.same('Pizzeria Roma AB', '556016-0680', ' pizzeria  roma ab. ', '5560160680'), isTrue);
      expect(CompanyPair.same('Pizzeria Roma AB', _org, 'Pizzeria Roma HB', _org), isFalse);
      expect(CompanyPair.same('Pizzeria Roma AB', _org, 'Pizzeria Roma AB', '556123-4567'), isFalse);
    });

    test('only an org number with a right check digit passes', () {
      expect(CompanyPair.orgValid('556016-0680'), isTrue);
      expect(CompanyPair.orgValid('5560160680'), isTrue);
      expect(CompanyPair.orgValid('556016-0681'), isFalse);
      expect(CompanyPair.orgValid('12345'), isFalse);
      expect(CompanyPair.orgValid(''), isFalse);
    });

    test('the hash is 64 hex characters and equal for the same pair', () async {
      final h = await CompanyPair.hash('Pizzeria Roma AB', _org);
      expect(h, '1d5dd5577498f1d8d09212a7762bf7fb26452946260be5767249e8fabf6e576b');
      expect(await CompanyPair.hash('pizzeria roma ab', '5560160680'), h);
    });
  });

  group('On the phone', () {
    late Repository repo;
    late _Server server;
    late ActivationService service;
    setUp(() async {
      sqfliteFfiInit();
      repo = Repository(await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
      server = _Server();
      service = ActivationService(
          repo, ActivationCloud(_Mem(), client: server.client, now: () => DateTime.utc(2026, 11, 16, 20)));
      await repo.saveProfile(const BusinessProfile(name: 'Pizzeria Roma AB', orgNumber: _org));
    });
    tearDown(() => repo.db.close());

    test('an order gives a one-week trial, locked to the company', () async {
      expect(await service.placeOrder(), isNull);
      var s = await repo.licenseState();
      expect(s.status, LicenseStatus.active);
      expect(s.license!.isTrial, isTrue);
      expect(s.license!.until, '2026-11-23');
      // changing the name stops the trial; putting it back starts it again
      await repo.saveProfile(const BusinessProfile(name: 'Pizzeria Roma HB', orgNumber: _org));
      expect((await repo.licenseState()).status, LicenseStatus.mismatch);
      await repo.saveProfile(const BusinessProfile(name: 'pizzeria roma ab', orgNumber: '5560160680'));
      expect((await repo.licenseState()).status, LicenseStatus.active);
      // the server got the order with the hash, not a second trial claim
      expect(server.writes.length, 2);
    });

    test('a pair that has had its trial gets no second one', () async {
      server.trialTaken = true;
      expect(await service.placeOrder(), isNull);
      expect((await repo.licenseState()).status, LicenseStatus.missing);
      expect((await repo.order())!.name, 'Pizzeria Roma AB');
    });

    test('a missing name or a wrong org number sends nothing', () async {
      await repo.saveProfile(const BusinessProfile(name: 'Pizzeria Roma AB', orgNumber: '556016-0681'));
      expect(await service.placeOrder(), contains('Företag'));
      expect(server.writes, isEmpty);
    });

    test('a code from the owner activates the app by itself, once', () async {
      await service.placeOrder();
      expect((await service.collect()).activated, isFalse);
      server.status = 'betald';
      expect((await service.collect()).status, 'betald');
      server.status = 'skickad';
      server.code = 'hej'; // not a valid code: refused, nothing changes
      expect((await service.collect()).activated, isFalse);
      expect((await repo.order()), isNotNull);
    });
  });
}
