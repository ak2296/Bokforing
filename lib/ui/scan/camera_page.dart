import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../app_icons.dart';

const _accent = Color(0xFF5FE0B0);
const _background = Color(0xFF0C1411);

/// Document camera with a framing guide. Returns the captured file paths
/// (several with "I delar") or null when cancelled. It never takes a photo
/// by itself; when the document looks steady it only suggests it.
class CameraPage extends StatefulWidget {
  final bool online;
  const CameraPage({super.key, this.online = false});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _permissionDenied = false;
  String? _error;
  bool _busy = false;
  bool _streaming = false;
  final List<String> _shots = [];

  /// "I delar": several photos of one long document.
  bool _inParts = false;

  bool _detected = false;
  bool _steady = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  double? _lastMean;
  DateTime? _steadySince;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.inactive) {
      _controller = null;
      _streaming = false;
      c?.dispose();
    } else if (state == AppLifecycleState.resumed && c == null) {
      _init();
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _permissionDenied = false;
    });
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _error = 'Ingen kamera hittades.');
        return;
      }
      final back = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first);
      final c = CameraController(back, ResolutionPreset.veryHigh,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await c.initialize();
      try {
        await c.setFlashMode(FlashMode.off);
      } on CameraException {
        // Not all devices support flash control.
      }
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
      await _startStream();
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code.contains('AccessDenied') || e.code.contains('Permission')) {
          _permissionDenied = true;
        } else {
          _error = 'Kameran kunde inte startas (${e.code}).';
        }
      });
    }
  }

  Future<void> _startStream() async {
    final c = _controller;
    if (c == null || _streaming) return;
    try {
      await c.startImageStream(_onFrame);
      _streaming = true;
    } catch (_) {
      // The live hint is optional; capture still works without it.
      _streaming = false;
    }
  }

  Future<void> _stopStream() async {
    final c = _controller;
    if (c == null || !_streaming) return;
    try {
      await c.stopImageStream();
    } catch (_) {}
    _streaming = false;
  }

  /// Cheap live check on the luminance plane: a bright area with some dark
  /// text in the centre counts as a document; a stable mean counts as steady.
  void _onFrame(CameraImage image) {
    final now = DateTime.now();
    if (now.difference(_lastFrame).inMilliseconds < 400) return;
    _lastFrame = now;
    if (image.planes.isEmpty) return;
    final y = image.planes.first;
    final w = image.width, h = image.height, stride = y.bytesPerRow;
    var bright = 0, dark = 0, n = 0, sum = 0;
    for (var row = (h * 0.15).round(); row < h * 0.85; row += 12) {
      for (var col = (w * 0.15).round(); col < w * 0.85; col += 12) {
        final i = row * stride + col;
        if (i >= y.bytes.length) continue;
        final v = y.bytes[i];
        sum += v;
        n++;
        if (v > 130) bright++;
        if (v < 90) dark++;
      }
    }
    if (n == 0) return;
    final mean = sum / n;
    final detected = bright > n * 0.5 && dark > n * 0.01;
    final stable = _lastMean != null && (mean - _lastMean!).abs() < 4;
    _lastMean = mean;
    if (detected && stable) {
      _steadySince ??= now;
    } else {
      _steadySince = null;
    }
    final steady = _steadySince != null && now.difference(_steadySince!).inMilliseconds > 1200;
    if (mounted && (detected != _detected || steady != _steady)) {
      setState(() {
        _detected = detected;
        _steady = steady;
      });
    }
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || _busy || !c.value.isInitialized) return;
    setState(() => _busy = true);
    try {
      await _stopStream();
      final file = await c.takePicture();
      _shots.add(file.path);
      if (!_inParts) {
        if (mounted) Navigator.pop(context, List<String>.of(_shots));
        return;
      }
      await _startStream();
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Bilden kunde inte tas (${e.code}). Försök igen.')));
      }
      await _startStream();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    Widget body;
    if (_permissionDenied) {
      body = _Message(
        icon: AppIcons.cameraOff,
        text: 'Appen behöver tillgång till kameran för att skanna dokument.\n\n'
            'Om du tidigare har nekat: öppna telefonens Inställningar → Appar → Bokföringsassistent → Behörigheter och tillåt Kamera.',
        action: FilledButton(onPressed: _retry, child: const Text('Försök igen')),
      );
    } else if (_error != null) {
      body = _Message(
          icon: AppIcons.error,
          text: _error!,
          action: FilledButton(onPressed: _retry, child: const Text('Försök igen')));
    } else if (c == null || !c.value.isInitialized) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final preview = c.value.previewSize;
      final hint = _steady
          ? 'Dokument upptäckt – håll stilla och tryck på knappen'
          : _detected
              ? 'Dokument upptäckt'
              : widget.online
                  ? 'Placera partnerns betalningsbekräftelse inom ramen'
                  : 'Placera fakturan eller Z-rapporten inom ramen';
      body = Column(
        children: [
          // The frame takes all the room between the title and the button.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: preview?.height ?? 720,
                        height: preview?.width ?? 1280,
                        child: CameraPreview(c),
                      ),
                    ),
                    CustomPaint(painter: _FramePainter(_detected)),
                    Positioned(left: 40, right: 40, top: 22, child: _Hint(hint, highlight: _detected)),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 14),
            child: Row(
              children: [
                Expanded(
                  child: _shots.isNotEmpty
                      ? Text('${_shots.length} ${_shots.length == 1 ? 'bild' : 'bilder'}',
                          textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 13))
                      : _ModeButton(
                          icon: AppIcons.file,
                          label: 'Hela',
                          selected: !_inParts,
                          onTap: () => setState(() => _inParts = false),
                        ),
                ),
                GestureDetector(
                  onTap: _busy ? null : _capture,
                  child: Semantics(
                    button: true,
                    label: 'Ta bild',
                    child: Container(
                      width: 68,
                      height: 68,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _steady ? _accent : Colors.white, width: 3),
                      ),
                      child: Container(
                        decoration: BoxDecoration(shape: BoxShape.circle, color: _steady ? _accent : Colors.white),
                        child: _busy
                            ? const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 3))
                            : null,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _shots.isNotEmpty
                      ? Center(
                          child: FilledButton.tonal(
                            onPressed: _busy ? null : () => Navigator.pop(context, List<String>.of(_shots)),
                            child: const Text('Klar'),
                          ),
                        )
                      : _ModeButton(
                          icon: AppIcons.files,
                          label: 'I delar',
                          selected: _inParts,
                          onTap: () => setState(() => _inParts = true),
                        ),
                ),
              ],
            ),
          ),
          if (_inParts && _shots.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('Börja överst. Ta en bild i taget med lite överlapp.',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ),
        ],
      );
    }
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        toolbarHeight: 44,
        titleTextStyle: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 14),
        title: Text(widget.online ? 'Skanna onlineförsäljning' : 'Skanna dokument'),
      ),
      body: SafeArea(child: body),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  final bool highlight;
  const _Hint(this.text, {required this.highlight});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: (highlight ? Colors.green.shade800 : Colors.black).withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
      );
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeButton({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? _accent : const Color(0xFFAEB9B3);
    return InkResponse(
      onTap: onTap,
      child: Semantics(
        selected: selected,
        button: true,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: selected ? FontWeight.w500 : FontWeight.w400)),
        ]),
      ),
    );
  }
}

/// Corner markers instead of a full box, so the document stays visible.
class _FramePainter extends CustomPainter {
  final bool detected;
  const _FramePainter(this.detected);

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 10.0, arm = 28.0, r = 12.0;
    final paint = Paint()
      ..color = detected ? _accent : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final right = size.width - inset, bottom = size.height - inset;
    void corner(double x, double y, double dx, double dy) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + dy * arm)
          ..lineTo(x, y + dy * r)
          ..quadraticBezierTo(x, y, x + dx * r, y)
          ..lineTo(x + dx * arm, y),
        paint,
      );
    }

    corner(inset, inset, 1, 1);
    corner(right, inset, -1, 1);
    corner(inset, bottom, 1, -1);
    corner(right, bottom, -1, -1);
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.detected != detected;
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget action;
  const _Message({required this.icon, required this.text, required this.action});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 48),
              const SizedBox(height: 16),
              Text(text, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              action,
            ],
          ),
        ),
      );
}
