import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Opens the user guide that ships with the app in the phone's PDF reader.
/// Without a PDF reader, the share menu offers it to another app instead.
Future<void> openUserGuide(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final data = await rootBundle.load('assets/anvandarguide.pdf');
    final file = File(p.join((await getTemporaryDirectory()).path, 'Quee-anvandarguide.pdf'));
    await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    final result = await OpenFilex.open(file.path, type: 'application/pdf');
    if (result.type == ResultType.done) return;
    if (result.type == ResultType.noAppToOpen) {
      messenger.showSnackBar(const SnackBar(content: Text('Ingen PDF-läsare hittades. Välj en app att öppna guiden med.')));
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')]));
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text('Guiden kunde inte öppnas: ${result.message}')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Guiden kunde inte öppnas: $e')));
  }
}
