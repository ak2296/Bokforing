import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../../app/app_controller.dart';
import '../../domain/classifier.dart';
import '../../domain/invoice_parser.dart';
import '../../domain/ocr_models.dart';
import '../../domain/online_parser.dart';
import '../../domain/payslip_parser.dart';
import '../../domain/reading_doubts.dart';
import '../../domain/text_merge.dart';
import '../../domain/z_report_parser.dart';
import '../../imaging/preprocess.dart';
import '../../ocr/ocr_service.dart';
import '../../ai/gemini_client.dart';
import '../review/ai_assist.dart';
import '../app_icons.dart';
import '../review/online_review_page.dart';
import '../review/payslip_review_page.dart';
import '../review/invoice_review_page.dart';
import '../review/z_review_page.dart';
import 'camera_page.dart';
import 'scan_context.dart';
import '../settings/activation_page.dart';

/// The states of one scan, shown to the user so it is always clear what is
/// happening and that nothing has been saved yet.
enum ScanState {
  idle,
  cameraPermissionRequired,
  scanning,
  processing,
  lowQuality,
  ocrFailed,
  documentUnknown,
  lowConfidence,
  mismatch,
  invoiceDetected,
  zReportDetected,
  failed,
}

/// Starts the camera and walks through processing to the review screen.
Future<void> startScan(BuildContext context, {bool online = false}) async {
  if (!await requireLicense(context) || !context.mounted) return;
  final paths = await Navigator.of(context)
      .push<List<String>>(MaterialPageRoute(builder: (_) => CameraPage(online: online)));
  if (paths == null || paths.isEmpty || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ScanFlowPage(photoPaths: paths, online: online)));
}

/// Reads a faktura saved as a PDF or an image, e.g. from an e-mail. A PDF is
/// turned into page images first; the rest works like a camera scan.
Future<void> importFile(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
    final source = picked.firstOrNull?.path;
    if (source == null || !context.mounted) return;
    await readSharedFile(context, source, pdf: source.toLowerCase().endsWith('.pdf'));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Filen kunde inte öppnas. Välj en PDF, JPG eller PNG, eller försök igen.')));
  }
}

/// Reads a PDF or image from [source]: picked in the app or shared to it from
/// another app, such as an e-mail attachment.
Future<void> readSharedFile(BuildContext context, String source, {required bool pdf}) async {
  if (!await requireLicense(context) || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final paths = <String>[];
    if (pdf) {
      // At most four pages: a faktura's totals are on the first pages.
      await for (final page in Printing.raster(await File(source).readAsBytes(), dpi: 200)) {
        final out = p.join(tmp.path, 'fil_${stamp}_${paths.length}.png');
        await File(out).writeAsBytes(await page.toPng());
        paths.add(out);
        if (paths.length == 4) break;
      }
    } else {
      final ext = p.extension(source).isEmpty ? '.jpg' : p.extension(source);
      final out = p.join(tmp.path, 'fil_$stamp$ext');
      await File(source).copy(out);
      paths.add(out);
    }
    if (paths.isEmpty || !context.mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ScanFlowPage(photoPaths: paths, online: false, fromFile: true)));
  } catch (e) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Filen kunde inte läsas. Kontrollera att den är en PDF, JPG eller PNG som inte är skadad eller låst.')));
  }
}

class ScanFlowPage extends StatefulWidget {
  final List<String> photoPaths;
  final bool online;

  /// A file, not a photo of paper: no paper edges to find, no photo checks.
  final bool fromFile;
  const ScanFlowPage({super.key, required this.photoPaths, required this.online, this.fromFile = false});

  @override
  State<ScanFlowPage> createState() => _ScanFlowPageState();
}

class _ScanFlowPageState extends State<ScanFlowPage> {
  ScanState _state = ScanState.processing;
  String _step = 'Förbättrar bilden…';

  /// How far the reading has come, 0 to 1, for the bar on the waiting screen.
  double _progress = 0.1;
  String? _error;
  final List<String> _processed = [];
  final List<QualityReport> _quality = [];
  final List<double> _aspects = [];
  OcrResult? _ocr;
  Classification? _classification;
  bool _aiUsable = false;
  DocumentType? _mismatchType;

  @override
  void initState() {
    super.initState();
    _process();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AiSettings.load(AppScope.read(context).repo).then((s) {
      if (mounted) setState(() => _aiUsable = s.usable);
    });
  }

  ScanContext _context(DocumentType type) => ScanContext(
        imagePaths: List.of(_processed),
        ocrText: _ocr?.rows().map((r) => r.text).join('\n') ?? '',
        type: type,
        classification: _classification,
      );

  Widget _aiButton() => !_aiUsable || widget.online || _processed.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            icon: const Icon(AppIcons.ai),
            label: const Text('Förbättrad analys online'),
            onPressed: () => runAiAnalysis(context, _context(DocumentType.unknown)),
          ),
        );

  Future<void> _process() async {
    try {
      if (widget.fromFile) {
        _processed.addAll(widget.photoPaths);
        await _recognize();
        return;
      }
      final tmp = await getTemporaryDirectory();
      for (final path in widget.photoPaths) {
        final bytes = await File(path).readAsBytes();
        final result = await compute(preprocessDocument, PreprocessRequest(bytes, corners: CameraPage.cornersFor(path)));
        final out = p.join(tmp.path, 'skanning_${DateTime.now().microsecondsSinceEpoch}.jpg');
        await File(out).writeAsBytes(result.jpeg);
        _processed.add(out);
        _quality.add(result.quality);
        if (result.quality.paperAspect != null) _aspects.add(result.quality.paperAspect!);
        try {
          await File(path).delete();
        } on FileSystemException {
          // Camera temp file; ignore.
        }
      }
      if (_quality.any((q) => !q.acceptable)) {
        if (!mounted) return;
        setState(() => _state = ScanState.lowQuality);
        return;
      }
      await _recognize();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = ScanState.failed;
        _error = '$e';
      });
    }
  }

  Future<void> _recognize() async {
    if (!mounted) return;
    setState(() {
      _state = ScanState.processing;
      _step = 'Läser texten…';
      _progress = 0.3;
    });
    final ocr = OcrService();
    try {
      final parts = <OcrResult>[];
      for (final path in _processed) {
        parts.add(await ocr.recognizeFile(path));
      }
      final merged = TextMerge.merge(parts);
      final visible = merged.text.replaceAll(RegExp(r'\s'), '');
      if (visible.length < 20) {
        if (!mounted) return;
        setState(() => _state = ScanState.ocrFailed);
        return;
      }
      _ocr = merged;
      if (!mounted) return;
      setState(() {
        _step = 'Tolkar dokumentet…';
        _progress = 0.6;
      });
      final c = const DocumentClassifier().classify(merged.text);
      _classification = c;
      final partners = await AppScope.read(context).repo.knownPartners();
      final onlinePaper = OnlineParser.looksLikeOnline(merged.text, partners: partners);
      if (widget.online) {
        // The online button was pressed: only stop if the paper is clearly
        // something else.
        if (!onlinePaper && c.isCertain && c.type == DocumentType.zReport) {
          if (!mounted) return;
          setState(() {
            _state = ScanState.mismatch;
            _mismatchType = DocumentType.zReport;
          });
          return;
        }
        await _openReview(DocumentType.onlineSale);
        return;
      }
      if (onlinePaper) {
        if (!mounted) return;
        setState(() {
          _state = ScanState.mismatch;
          _mismatchType = DocumentType.onlineSale;
        });
        return;
      }
      if (c.type == DocumentType.unknown && c.confidence == 0) {
        if (!mounted) return;
        setState(() => _state = ScanState.documentUnknown);
        return;
      }
      if (!c.isCertain) {
        if (!mounted) return;
        setState(() => _state = ScanState.lowConfidence);
        return;
      }
      await _openReview(c.type);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = ScanState.failed;
        _error = '$e';
      });
    } finally {
      await ocr.close();
    }
  }

  /// A reading with doubts (a key field missing or uncertain, rows that do
  /// not add up) on a tilted photo is read a second time with the photo turned
  /// by the measured tilt, and the reading with fewer doubts is kept. Slower,
  /// so only done when needed; the waiting screen says so. Used for every
  /// type of document; [parse] and [doubts] are those of the document's type.
  Future<(OcrResult, T)> _readAgain<T>(OcrResult first, T Function(OcrResult) parse, int Function(T) doubts) async {
    var bestOcr = first;
    var best = parse(first);
    final tilt = first.tiltDegrees;
    if (doubts(best) == 0 || tilt == null || tilt.abs() < 0.3 || _processed.length != 1 || !mounted) {
      return (bestOcr, best);
    }
    setState(() {
      _step = 'Läser en gång till, noggrannare…';
      _progress = 0.8;
    });
    final ocr = OcrService();
    try {
      for (final candidate in await ocr.recognizeStraightened(_processed.single, tilt.abs())) {
        final d = parse(candidate);
        if (doubts(d) < doubts(best)) {
          best = d;
          bestOcr = candidate;
        }
      }
    } catch (_) {
      // The first reading stands.
    } finally {
      await ocr.close();
    }
    return (bestOcr, best);
  }

  Future<void> _openReview(DocumentType detected) async {
    var ocr = _ocr!;
    // A självfaktura with the partner's invoice is reviewed as an online sale
    // first, then as an invoice.
    final type = OnlineParser.isCombined(ocr.rows().map((r) => r.text).join('\n')) ? DocumentType.onlineSale : detected;
    final controller = AppScope.read(context);
    OnlineDraft? onlineDraft;
    PayslipDraft? slipDraft;
    InvoiceDraft? invoiceDraft;
    ZReportDraft? zDraft;
    if (type == DocumentType.onlineSale) {
      final parser = OnlineParser(knownPartners: await controller.repo.knownPartners());
      final r = await _readAgain(ocr, parser.parse, onlineDoubts);
      ocr = r.$1;
      onlineDraft = r.$2;
    } else if (type == DocumentType.payslip) {
      final r = await _readAgain(ocr, const PayslipParser().parse, payslipDoubts);
      ocr = r.$1;
      slipDraft = r.$2;
    } else if (type == DocumentType.invoice) {
      final aspect = widget.photoPaths.length == 1 && _aspects.length == 1 ? _aspects.single : null;
      final profile = await controller.repo.profile();
      final parser = InvoiceParser(
        knownSuppliers: await controller.repo.knownSuppliers(),
        ownName: profile.name,
        ownNames: await controller.repo.ownNames(),
        ownOrgNumber: profile.orgNumber,
        ownAddress: profile.address,
      );
      final r = await _readAgain(ocr, (o) => parser.parse(o, paperAspect: aspect), invoiceDoubts);
      ocr = r.$1;
      var draft = r.$2;
      // What the user taught by correcting this supplier's papers before.
      final supplier = draft.supplier.value;
      if (supplier != null) {
        final hints = await controller.repo.supplierHints(supplier);
        if (hints.isNotEmpty) draft = draft.withHints([for (final row in ocr.rows()) row.text], hints);
      }
      invoiceDraft = draft;
    } else {
      final parser = ZReportParser(
        await controller.repo.categories(),
        aliases: await controller.repo.categoryAliases(),
        ignored: await controller.repo.ignoredZLabels(),
        usage: await controller.repo.categoryUsage(),
      );
      final r = await _readAgain(ocr, parser.parse, ZReportParser.doubtsOf);
      ocr = r.$1;
      zDraft = r.$2;
    }
    _ocr = ocr;
    final ctx = ScanContext(
      imagePaths: List.of(_processed),
      ocrText: ocr.rows().map((r) => r.text).join('\n'),
      ocrJson: widget.photoPaths.length == 1 ? ocr.toJsonString() : null,
      type: type,
      classification: _classification,
    );
    if (!mounted) return;
    setState(() => _state = type == DocumentType.invoice ? ScanState.invoiceDetected : ScanState.zReportDetected);
    final Widget page = onlineDraft != null
        ? OnlineReviewPage(draft: onlineDraft, scan: ctx)
        : slipDraft != null
            ? PayslipReviewPage(draft: slipDraft, scan: ctx)
            : invoiceDraft != null
                ? InvoiceReviewPage(draft: invoiceDraft, scan: ctx)
                : ZReviewPage(draft: zDraft!, scan: ctx);
    // The review page handles saving and leaving.
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _rescan() async {
    for (final path in _processed) {
      try {
        await File(path).delete();
      } on FileSystemException {
        // ignore
      }
    }
    if (!mounted) return;
    final navigator = Navigator.of(context);
    navigator.pop();
    await startScan(navigator.context, online: widget.online);
  }

  Future<void> _manual(DocumentType type) async {
    final Widget page = switch (type) {
      DocumentType.invoice => const InvoiceReviewPage(),
      DocumentType.payslip => const PayslipReviewPage(),
      _ => const ZReviewPage(),
    };
    await Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => page));
  }

  Widget _manualChoice() => widget.online
      ? OutlinedButton(
          onPressed: () => Navigator.of(context)
              .pushReplacement(MaterialPageRoute(builder: (_) => const OnlineReviewPage())),
          child: const Text('Fyll i manuellt'),
        )
      : _ManualButtons(onPick: _manual);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget body;
    switch (_state) {
      case ScanState.processing:
      case ScanState.invoiceDetected:
      case ScanState.zReportDetected:
      case ScanState.idle:
      case ScanState.scanning:
      case ScanState.cameraPermissionRequired:
        body = Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 240,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: _progress, minHeight: 6),
              ),
            ),
            const SizedBox(height: 16),
            Text(_step),
            const SizedBox(height: 8),
            const Text('Inget sparas förrän du har godkänt uppgifterna.'),
          ]),
        );
      case ScanState.lowQuality:
        final issues = {for (final q in _quality) ...q.issues}.toList();
        body = _Panel(
          icon: AppIcons.imageOff,
          title: 'Bildkvaliteten är för låg',
          children: [
            for (final i in issues)
              ListTile(
                leading: const Icon(AppIcons.warning),
                title: Text(i.title),
                subtitle: Text(i.advice),
              ),
          ],
          primary: FilledButton(onPressed: _rescan, child: const Text('Skanna igen')),
          secondary: OutlinedButton(
            onPressed: _recognize,
            child: const Text('Använd ändå'),
          ),
        );
      case ScanState.ocrFailed:
        body = _Panel(
          icon: AppIcons.text,
          title: 'Ingen text kunde läsas',
          children: [
            const Text('Prova att ta bilden närmare och med bättre ljus. För långa kvitton: använd "Långt dokument".'),
            _aiButton(),
          ],
          primary: FilledButton(onPressed: _rescan, child: const Text('Skanna igen')),
          secondary: _manualChoice(),
        );
      case ScanState.documentUnknown:
        body = _Panel(
          icon: AppIcons.help,
          title: 'Dokumentet känns inte igen',
          children: [
            const Text('Det ser inte ut som en faktura, ett kvitto eller en Z-rapport.'),
            _aiButton(),
          ],
          primary: FilledButton(onPressed: _rescan, child: const Text('Skanna igen')),
          secondary: Column(children: [
            OutlinedButton(onPressed: () => _openReview(DocumentType.invoice), child: const Text('Det är en faktura')),
            OutlinedButton(onPressed: () => _openReview(DocumentType.zReport), child: const Text('Det är en Z-rapport')),
          ]),
        );
      case ScanState.mismatch:
        final toOnline = _mismatchType == DocumentType.onlineSale;
        body = _Panel(
          icon: AppIcons.help,
          title: toOnline ? 'Det här ser ut som onlineförsäljning' : 'Det här ser ut som en Z-rapport',
          children: [
            Text(toOnline
                ? 'Utbetalningar från en partner är försäljning, inte en utgift. Vill du registrera den som onlineförsäljning?'
                : 'Du tryckte på Skanna onlineförsäljning. Vill du byta till Z-rapport?'),
          ],
          primary: FilledButton(
            onPressed: () => _openReview(_mismatchType!),
            child: Text(toOnline ? 'Ja, onlineförsäljning' : 'Ja, Z-rapport'),
          ),
          secondary: OutlinedButton(
            onPressed: () {
              if (toOnline) {
                final c = _classification!;
                _openReview(c.type == DocumentType.zReport ? DocumentType.zReport : DocumentType.invoice);
              } else {
                _openReview(DocumentType.onlineSale);
              }
            },
            child: Text(toOnline ? 'Nej, fortsätt som vanligt' : 'Nej, onlineförsäljning'),
          ),
        );
      case ScanState.lowConfidence:
        final c = _classification!;
        body = _Panel(
          icon: AppIcons.help,
          title: 'Vi är osäkra på dokumenttypen.',
          children: [
            Text('Bästa gissning: ${c.type.label} (${(c.confidence * 100).round()} % säkerhet). Välj vad det är:'),
            _aiButton(),
          ],
          primary: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(onPressed: () => _openReview(DocumentType.invoice), child: const Text('Faktura / kvitto')),
              const SizedBox(height: 8),
              FilledButton(onPressed: () => _openReview(DocumentType.zReport), child: const Text('Z-rapport')),
              const SizedBox(height: 8),
              FilledButton(onPressed: () => _openReview(DocumentType.payslip), child: const Text('Lönebesked')),
            ],
          ),
          secondary: OutlinedButton(
            onPressed: () => setState(() => _state = ScanState.documentUnknown),
            child: const Text('Annat'),
          ),
        );
      case ScanState.failed:
        body = _Panel(
          icon: AppIcons.error,
          title: 'Något gick fel',
          children: [Text('Inget har sparats. ${_error ?? ''}')],
          primary: FilledButton(onPressed: _rescan, child: const Text('Skanna igen')),
          secondary: _manualChoice(),
        );
    }
    return Scaffold(
      appBar: AppBar(title: Text('Skanning', style: t.titleLarge)),
      body: SafeArea(child: body),
    );
  }
}

class _ManualButtons extends StatelessWidget {
  final ValueChanged<DocumentType> onPick;
  const _ManualButtons({required this.onPick});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(onPressed: () => onPick(DocumentType.invoice), child: const Text('Fyll i faktura / kvitto manuellt')),
          OutlinedButton(onPressed: () => onPick(DocumentType.zReport), child: const Text('Fyll i Z-rapport manuellt')),
          OutlinedButton(onPressed: () => onPick(DocumentType.payslip), child: const Text('Fyll i lönebesked manuellt')),
        ],
      );
}

class _Panel extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  final Widget primary;
  final Widget secondary;
  const _Panel({
    required this.icon,
    required this.title,
    required this.children,
    required this.primary,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ...children,
          const SizedBox(height: 20),
          primary,
          const SizedBox(height: 8),
          secondary,
        ],
      );
}
