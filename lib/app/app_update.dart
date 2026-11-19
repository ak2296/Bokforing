import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The build number CI gave this build (minutes since 1970). 0 when the app
/// was not built by CI (tests, local runs): then no update is offered.
const kBuildNumber = int.fromEnvironment('BUILD_NUMBER');

/// Off in a Google Play build (`--dart-define=SELF_UPDATE=false`): Play updates
/// the app itself and does not allow an app to install other APK files.
const kSelfUpdate = bool.fromEnvironment('SELF_UPDATE', defaultValue: true);

/// A release in the download repository that the app can install.
class UpdateInfo {
  final int build;
  final String name;
  final String apkUrl;
  final int size;
  const UpdateInfo(this.build, this.name, this.apkUrl, this.size);

  bool isNewerThan(int installed) => installed > 0 && build > installed;
}

/// What a look at the download repository found: [reached] is false when
/// GitHub could not be read at all (no network, rate limit); [info] is null
/// when the latest release carries no build number, as releases made before
/// the update feature do, so there is nothing to compare with.
class UpdateCheck {
  final bool reached;
  final UpdateInfo? info;
  const UpdateCheck(this.reached, this.info);
}

/// Looks for a newer release of the app and installs it over the old one.
/// Installing an APK signed with the same key keeps all data; the update
/// never touches the database.
class AppUpdater {
  const AppUpdater._();

  static const releasesUrl = 'https://api.github.com/repos/ak2296/quee/releases/latest';
  static const apkName = 'Quee.apk';

  /// The release JSON from GitHub. The release text carries the build number on
  /// a line "build: 29712345"; the app file is the asset named `Quee.apk`.
  /// Null when either is missing, so a release made without them is ignored.
  static UpdateInfo? parse(Object? json) {
    if (json is! Map) return null;
    final body = '${json['body'] ?? ''}';
    final build = int.tryParse(RegExp(r'build:\s*(\d+)', caseSensitive: false).firstMatch(body)?.group(1) ?? '');
    final assets = json['assets'];
    if (build == null || assets is! List) return null;
    for (final a in assets) {
      if (a is Map && a['name'] == apkName && a['browser_download_url'] is String) {
        return UpdateInfo(
          build,
          '${json['name'] ?? json['tag_name'] ?? ''}',
          a['browser_download_url'] as String,
          (a['size'] as num?)?.toInt() ?? 0,
        );
      }
    }
    return null;
  }

  /// Looks at the latest release.
  static Future<UpdateCheck> check({http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final r = await c
          .get(Uri.parse(releasesUrl), headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'Quee'})
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return const UpdateCheck(false, null);
      return UpdateCheck(true, parse(jsonDecode(r.body)));
    } catch (_) {
      return const UpdateCheck(false, null);
    } finally {
      if (client == null) c.close();
    }
  }

  /// Downloads the APK to the app's cache, reporting progress. A slow or dropped
  /// connection carries on from where it stopped (up to [attempts] tries); it
  /// throws when the file still is not whole, so a half file is never handed to the
  /// installer. Older update files in the cache are removed first.
  static Future<File> download(UpdateInfo u, void Function(int received, int total) onProgress,
      {http.Client? client, Directory? into, int attempts = 6}) async {
    final c = client ?? http.Client();
    try {
      final dir = into ?? await getTemporaryDirectory();
      for (final f in dir.listSync()) {
        final name = p.basename(f.path);
        if (f is File && name.startsWith('Quee-') && name.endsWith('.apk')) f.deleteSync();
      }
      final file = File(p.join(dir.path, 'Quee-${u.build}.apk'));
      var got = 0;
      var total = u.size;
      Object? last;
      for (var attempt = 0; attempt < attempts; attempt++) {
        try {
          final req = http.Request('GET', Uri.parse(u.apkUrl))..headers['User-Agent'] = 'Quee';
          if (got > 0) req.headers['Range'] = 'bytes=$got-';
          final res = await c.send(req).timeout(const Duration(seconds: 30));
          if (res.statusCode != 200 && res.statusCode != 206) throw HttpException('HTTP ${res.statusCode}');
          final resumed = res.statusCode == 206 && got > 0;
          if (!resumed) {
            got = 0;
            total = res.contentLength ?? u.size;
          }
          final sink = file.openWrite(mode: resumed ? FileMode.append : FileMode.write);
          try {
            await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
              got += chunk.length;
              sink.add(chunk);
              onProgress(got, total);
            }
          } finally {
            await sink.close();
          }
          if (total <= 0 || got == total) return file;
          last = const HttpException('Hämtningen avbröts');
        } catch (e) {
          last = e;
        }
      }
      if (file.existsSync()) await file.delete();
      throw last ?? const HttpException('Hämtningen misslyckades');
    } finally {
      if (client == null) c.close();
    }
  }

  /// Why a download failed, in plain Swedish with the technical name last, so the
  /// owner can say what went wrong.
  static String failureReason(Object e) {
    final what = switch (e) {
      TimeoutException() => 'Anslutningen svarade inte',
      SocketException() => 'Ingen kontakt med nedladdningen',
      FileSystemException() => 'Filen kunde inte sparas, kanske är telefonens minne fullt',
      HttpException(:final message) => message,
      _ => 'Okänt fel',
    };
    return '$what (${e.runtimeType})';
  }

  /// Hands the APK to Android's installer. The first time, Android asks the
  /// user to allow Quee to install apps.
  static Future<OpenResult> install(File apk) => OpenFilex.open(apk.path, type: 'application/vnd.android.package-archive');
}
