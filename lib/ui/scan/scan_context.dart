import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/app_controller.dart';
import '../../app/settings_keys.dart';
import '../../domain/classifier.dart';
import '../../imaging/preprocess.dart';

/// What a scan produced, carried to the review screen. Nothing here is in
/// the database until the user confirms.
class ScanContext {
  final List<String> imagePaths;
  final String ocrText;
  final String? ocrJson;
  final DocumentType type;
  final Classification? classification;

  const ScanContext({
    required this.imagePaths,
    required this.ocrText,
    this.ocrJson,
    required this.type,
    this.classification,
  });

  /// Stores the scan record (and the images when "Behåll originalbilder" is
  /// on). Called only from the confirm action. Returns the scan id.
  Future<int> persist(AppController c) async {
    final keep = await c.repo.boolSetting(SettingsKeys.keepImages);
    final kept = <String>[];
    if (keep) {
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'skanningar'));
      await dir.create(recursive: true);
      for (final path in imagePaths) {
        final target = p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}_${p.basename(path)}');
        // A smaller copy than the one read by OCR: still clear to read, a
        // fraction of the space.
        try {
          await File(target).writeAsBytes(await compute(compactJpeg, await File(path).readAsBytes()));
        } catch (_) {
          await File(path).copy(target);
        }
        kept.add(target);
      }
    }
    final id = await c.repo.saveScan(
      docType: type.name,
      ocrText: ocrText,
      // The word layout is only needed while reviewing (for the online
      // analysis); the text is enough afterwards.
      ocrJson: null,
      imagePath: kept.isEmpty ? null : kept.join(';'),
    );
    await discardImages();
    return id;
  }

  /// Deletes the temporary processed images.
  Future<void> discardImages() async {
    for (final path in imagePaths) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } on FileSystemException {
        // Temporary files; the OS cleans the cache directory anyway.
      }
    }
  }
}
