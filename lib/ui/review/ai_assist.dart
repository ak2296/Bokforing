import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../ai/ai_result.dart';
import '../../ai/gemini_client.dart';
import '../../app/app_controller.dart';
import '../../domain/classifier.dart';
import '../scan/scan_context.dart';
import 'invoice_review_page.dart';
import 'z_review_page.dart';

/// Shown every time before anything is sent. Returns true only when the
/// user taps "Skicka till Google".
Future<bool> aiConsent(BuildContext context, {required int imageCount}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.cloud_upload_outlined),
      title: const Text('Förbättrad analys online'),
      content: SingleChildScrollView(
        child: Text(
          'Om du fortsätter skickas ${imageCount == 1 ? 'bilden' : '$imageCount bilder'} av dokumentet via internet till Google '
          '(Gemini API) för tolkning.\n\n'
          '• Bilden innehåller allt som står på dokumentet, t.ex. leverantör, belopp, datum och kundnummer.\n'
          '• Enligt Googles villkor för den kostnadsfria nivån kan innehållet användas för att förbättra Googles '
          'tjänster och granskas av människor.\n'
          '• Inget annat skickas: inte din databas, inte andra dokument.\n'
          '• Svaret är bara ett förslag. Appen kontrollerar beloppen och du godkänner allt själv innan något sparas.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Avbryt')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Skicka till Google')),
      ],
    ),
  );
  return ok == true;
}

/// Runs the online analysis for [scan] after consent and opens a new review
/// screen with the suggestion. Returns false when nothing was opened.
Future<bool> runAiAnalysis(BuildContext context, ScanContext scan) async {
  final controller = AppScope.read(context);
  final settings = await AiSettings.load(controller.repo);
  if (!context.mounted) return false;
  if (!settings.usable) {
    await _message(context, 'Förbättrad analys är inte aktiverad',
        'Aktivera den och klistra in din API-nyckel under Inställningar → Förbättrad analys.');
    return false;
  }
  if (!await aiConsent(context, imageCount: scan.imagePaths.length) || !context.mounted) return false;

  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('Skickar och väntar på svar…')),
        ]),
      ),
    ),
  );

  final client = GeminiClient(apiKey: settings.apiKey!, model: settings.model);
  AiResult? result;
  String? error;
  try {
    final images = <Uint8List>[for (final p in scan.imagePaths) await File(p).readAsBytes()];
    result = await client.analyze(images);
  } on AiException catch (e) {
    error = e.message;
  } catch (e) {
    error = 'Oväntat fel: $e';
  } finally {
    client.close();
  }
  navigator.pop(); // progress dialog
  if (!context.mounted) return false;

  if (error != null) {
    await _message(context, 'Förbättrad analys misslyckades', '$error\n\nDu kan fortsätta med uppgifterna som lästes av i telefonen.');
    return false;
  }
  final r = result!;
  Widget page;
  final aiScan = ScanContext(
    imagePaths: scan.imagePaths,
    ocrText: scan.ocrText,
    ocrJson: scan.ocrJson,
    type: r.type,
    classification: scan.classification,
  );
  switch (r.type) {
    case DocumentType.invoice:
      page = InvoiceReviewPage(draft: r.toInvoiceDraft(), scan: aiScan, fromAi: true);
    case DocumentType.zReport:
      final cats = await controller.repo.categories();
      final aliases = await controller.repo.categoryAliases();
      page = ZReviewPage(draft: r.toZReportDraft(cats, aliases), scan: aiScan, fromAi: true);
    case DocumentType.unknown:
      if (context.mounted) {
        await _message(context, 'Dokumentet kändes inte igen',
            'Inte heller den förbättrade analysen kunde se att det är en faktura eller en Z-rapport.');
      }
      return false;
  }
  if (!context.mounted) return false;
  navigator.pushReplacement(MaterialPageRoute(builder: (_) => page));
  return true;
}

Future<void> _message(BuildContext context, String title, String text) => showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );

/// Offered on the review screen only when the offline checks failed and the
/// owner has enabled the feature.
class AiOfferCard extends StatefulWidget {
  final ScanContext scan;
  final List<String> reasons;
  const AiOfferCard({super.key, required this.scan, required this.reasons});

  @override
  State<AiOfferCard> createState() => _AiOfferCardState();
}

class _AiOfferCardState extends State<AiOfferCard> {
  bool? _usable;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_usable == null) {
      AiSettings.load(AppScope.read(context).repo).then((s) {
        if (mounted) setState(() => _usable = s.usable);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_usable != true || widget.reasons.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Telefonen kunde inte läsa allt säkert:', style: TextStyle(fontWeight: FontWeight.w600)),
            for (final r in widget.reasons) Text('• $r'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Förbättrad analys online'),
              onPressed: () => runAiAnalysis(context, widget.scan),
            ),
          ],
        ),
      ),
    );
  }
}
