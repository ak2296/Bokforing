import 'dart:convert';
import 'dart:io';

import 'package:bokforing/app/app_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> _release({String body = 'Nya funktioner\nbuild: 29712345', String asset = 'Quee.apk'}) => {
      'name': 'Quee 2026-11-14',
      'tag_name': 'v2026.11.14',
      'body': body,
      'assets': [
        {'name': asset, 'browser_download_url': 'https://example.test/$asset', 'size': 110000000},
      ],
    };

void main() {
  group('AppUpdater.parse', () {
    test('reads build number, name, file address and size', () {
      final u = AppUpdater.parse(_release())!;
      expect(u.build, 29712345);
      expect(u.name, 'Quee 2026-11-14');
      expect(u.apkUrl, 'https://example.test/Quee.apk');
      expect(u.size, 110000000);
    });

    test('a release without a build line or without Quee.apk is ignored', () {
      expect(AppUpdater.parse(_release(body: 'ingen rad')), isNull);
      expect(AppUpdater.parse(_release(asset: 'app-debug.apk')), isNull);
      expect(AppUpdater.parse('not a map'), isNull);
    });

    test('newer means a higher build number; an unknown own build never updates', () {
      final u = AppUpdater.parse(_release())!;
      expect(u.isNewerThan(29712344), isTrue);
      expect(u.isNewerThan(29712345), isFalse);
      expect(u.isNewerThan(0), isFalse);
    });
  });

  group('AppUpdater.check', () {
    test('reads the release when GitHub answers with one that has a build number', () async {
      final ok = MockClient((_) async => http.Response(jsonEncode(_release()), 200));
      final r = await AppUpdater.check(client: ok);
      expect(r.reached, isTrue);
      expect(r.info!.build, 29712345);
    });

    test('a release without a build number is reached but has nothing to compare', () async {
      final old = MockClient((_) async => http.Response(jsonEncode(_release(body: 'Preliminär skatt per år.')), 200));
      final r = await AppUpdater.check(client: old);
      expect(r.reached, isTrue);
      expect(r.info, isNull);
    });

    test('errors and unreadable answers count as not reached', () async {
      final limited = MockClient((_) async => http.Response('{}', 403));
      expect((await AppUpdater.check(client: limited)).reached, isFalse);
      final broken = MockClient((_) async => http.Response('not json', 200));
      expect((await AppUpdater.check(client: broken)).reached, isFalse);
      final down = MockClient((_) async => throw const SocketException('no network'));
      expect((await AppUpdater.check(client: down)).reached, isFalse);
    });
  });

  group('AppUpdater.download', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('quee_update'));
    tearDown(() => dir.deleteSync(recursive: true));

    const info = UpdateInfo(7, 'Quee', 'https://example.test/Quee.apk', 0);

    test('writes the file and reports progress', () async {
      final bytes = List<int>.generate(1000, (i) => i % 256);
      final client = MockClient.streaming((req, _) async => http.StreamedResponse(
          Stream.fromIterable([bytes.sublist(0, 400), bytes.sublist(400)]), 200,
          contentLength: bytes.length));
      final seen = <int>[];
      final file = await AppUpdater.download(info, (got, total) => seen.add(got), client: client, into: dir);
      expect(file.readAsBytesSync(), bytes);
      expect(seen, [400, 1000]);
    });

    test('a download that is cut short is deleted and fails', () async {
      final client = MockClient.streaming(
          (req, _) async => http.StreamedResponse(Stream.value([1, 2, 3]), 200, contentLength: 10));
      await expectLater(AppUpdater.download(info, (_, _) {}, client: client, into: dir), throwsA(isA<HttpException>()));
      expect(dir.listSync(), isEmpty);
    });
  });
}
