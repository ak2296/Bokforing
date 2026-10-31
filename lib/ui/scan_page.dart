import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../imaging/preprocess.dart';
import '../ocr/mlkit_ocr.dart';

class ScanResult {
  const ScanResult(this.text, this.imagePath, this.rowCount);
  final String text, imagePath;
  final int rowCount;
}

enum ScanStage { initializing, permissionRequired, ready, processing, lowQuality, ocrFailed, failed }

/// Camera → preprocessing → quality check → OCR. Pops a [ScanResult].
/// Nothing is saved here; the review step decides what is recorded.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  CameraController? _cam;
  ScanStage _stage = ScanStage.initializing;
  String? _error, _processedPath;
  PreprocessResult? _pre;
  bool _torch = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _init();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _cam?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _stage = ScanStage.initializing);
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cams.first);
      final c = CameraController(back, ResolutionPreset.ultraHigh, enableAudio: false);
      await c.initialize();
      await c.setFlashMode(FlashMode.off);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _cam = c;
        _stage = ScanStage.ready;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = e.code.toLowerCase().contains('access')
            ? ScanStage.permissionRequired
            : ScanStage.failed;
        _error = e.description ?? e.code;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = ScanStage.failed;
        _error = '$e';
      });
    }
  }

  Future<void> _capture() async {
    final c = _cam;
    if (c == null || !c.value.isInitialized || _stage != ScanStage.ready) return;
    setState(() => _stage = ScanStage.processing);
    try {
      final shot = await c.takePicture();
      final pre = await preprocessDocument(await shot.readAsBytes());
      final out = File('${shot.path}.scan.jpg');
      await out.writeAsBytes(pre.jpeg);
      _pre = pre;
      _processedPath = out.path;
      if (!mounted) return;
      if (pre.issues.isNotEmpty) {
        setState(() => _stage = ScanStage.lowQuality);
      } else {
        await _runOcr();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = ScanStage.failed;
        _error = '$e';
      });
    }
  }

  Future<void> _runOcr() async {
    setState(() => _stage = ScanStage.processing);
    try {
      final doc = await recognizeDocument(_processedPath!);
      if (!mounted) return;
      if (doc.fullText.trim().length < 10) {
        setState(() => _stage = ScanStage.ocrFailed);
        return;
      }
      Navigator.of(context).pop(ScanResult(doc.toText(), _processedPath!, doc.rows().length));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = ScanStage.failed;
        _error = '$e';
      });
    }
  }

  Future<void> _again() async {
    try {
      await _cam?.resumePreview();
    } catch (_) {}
    if (mounted) setState(() => _stage = ScanStage.ready);
  }

  Future<void> _toggleTorch() async {
    final c = _cam;
    if (c == null) return;
    _torch = !_torch;
    try {
      await c.setFlashMode(_torch ? FlashMode.torch : FlashMode.off);
    } catch (_) {
      _torch = false;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _stage == ScanStage.ready ? Colors.black : null,
      appBar: AppBar(title: const Text('Skanna dokument')),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    return switch (_stage) {
        ScanStage.initializing || ScanStage.processing => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_stage == ScanStage.processing ? 'Bearbetar dokumentet…' : 'Startar kameran…'),
            ]),
          ),
        ScanStage.ready => _preview(),
        ScanStage.permissionRequired => _message(
            'Kameran behöver tillstånd',
            'Appen använder kameran för att skanna dokument. Bilderna lämnar inte telefonen. '
                'Du kan även ge tillstånd i telefonens inställningar.',
            [FilledButton(onPressed: _init, child: const Text('Försök igen'))]),
        ScanStage.ocrFailed => _message('Ingen text hittades',
            'Texten kunde inte läsas. Försök igen med bättre ljus och håll telefonen stilla.',
            [FilledButton(onPressed: _again, child: const Text('Skanna igen'))]),
        ScanStage.failed => _message('Något gick fel', _error ?? 'Okänt fel.',
            [FilledButton(onPressed: _init, child: const Text('Försök igen'))]),
        ScanStage.lowQuality => _quality(),
    };
  }

  Widget _message(String title, String body, List<Widget> actions) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            SelectableText(body, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ...actions,
          ]),
        ),
      );

  Widget _preview() {
    final c = _cam!;
    return ColoredBox(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
        Center(
          child: AspectRatio(
            aspectRatio: 1 / c.value.aspectRatio,
            child: Stack(fit: StackFit.expand, children: [
              CameraPreview(c),
              CustomPaint(painter: _FramePainter()),
            ]),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: 12,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.black54, borderRadius: BorderRadius.circular(8)),
              child: const Text('Placera fakturan eller Z-rapporten inom ramen',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            IconButton(
              onPressed: _toggleTorch,
              tooltip: 'Ficklampa',
              icon: Icon(_torch ? Icons.flash_on : Icons.flash_off, color: Colors.white),
            ),
            FloatingActionButton.large(
              onPressed: _capture,
              tooltip: 'Ta bild',
              child: const Icon(Icons.camera_alt),
            ),
            const SizedBox(width: 48),
          ]),
        ),
      ]),
    );
  }

  Widget _quality() {
    final pre = _pre!;
    final blocking = pre.issues.any((i) => i.blocking);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(blocking ? 'Bildkvaliteten är för låg' : 'Kontrollera bildkvaliteten',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final i in pre.issues)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(i.blocking ? Icons.error_outline : Icons.warning_amber_outlined,
                color: i.blocking ? Colors.red.shade700 : Colors.orange.shade800),
            title: Text(i.message),
            subtitle: Text(i.hint),
          ),
        Expanded(
          child: Center(child: Image.file(File(_processedPath!), fit: BoxFit.contain)),
        ),
        Text(
            'Mätvärden: ljus ${pre.brightness.round()}, skärpa ${pre.sharpness.round()}, '
            'lutning ${pre.skewDegrees.toStringAsFixed(1)}°',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: FilledButton(onPressed: _again, child: const Text('Skanna igen'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: _runOcr, child: const Text('Använd ändå'))),
        ]),
      ]),
    );
  }
}

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(size.width * kFrameInsetX, size.height * kFrameInsetY,
        size.width * (1 - kFrameInsetX), size.height * (1 - kFrameInsetY));
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(12));
    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rr)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = Colors.black54);
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
