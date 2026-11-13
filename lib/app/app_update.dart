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

  /// The latest release, or null when it cannot be read (no network, rate limit).
  static Future<UpdateInfo?> latest({http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final r = await c
          .get(Uri.parse(releasesUrl), headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'Quee'})
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      return parse(jsonDecode(r.body));
    } catch (_) {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  /// Downloads the APK to the app's cache, reporting progress. Throws when the
  /// download is cut short, so a half file is never handed to the installer.
  static Future<File> download(UpdateInfo u, void Function(int received, int total) onProgress,
      {http.Client? client, Directory? into}) async {
    final c = client ?? http.Client();
    try {
      final req = http.Request('GET', Uri.parse(u.apkUrl))..headers['User-Agent'] = 'Quee';
      final res = await c.send(req);
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength ?? u.size;
      final dir = into ?? await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'Quee-${u.build}.apk'));
      final sink = file.openWrite();
      var got = 0;
      try {
        await for (final chunk in res.stream) {
          got += chunk.length;
          sink.add(chunk);
          onProgress(got, total);
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && got != total) {
        await file.delete();
        throw const HttpException('Hämtningen avbröts');
      }
      return file;
    } finally {
      if (client == null) c.close();
    }
  }

  /// Hands the APK to Android's installer. The first time, Android asks the
  /// user to allow Quee to install apps.
  static Future<OpenResult> install(File apk) => OpenFilex.open(apk.path, type: 'application/vnd.android.package-archive');
}
