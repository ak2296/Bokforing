import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../app_icons.dart';

const _accent = Color(0xFF5FE0B0);
const _background = Color(0xFF0C1411);

/// Document camera with a framing guide. Returns the captured file paths
/// (several with "I delar") or null when cancelled. It never takes a photo
/// by itself; when the document looks steady it only suggests it.
class CameraPage extends StatefulWidget {
  final bool online;
  const CameraPage({super.key, this.online = false});

  static final _frames = <String, List<double>>{};

  /// The page found in the viewfinder when [path] was taken, as fractions of
  /// the upright photo (left, top, right, bottom), or null.
  static List<double>? frameFor(String path) => _frames.remove(path);

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

  /// Corners of the page in the viewfinder, as fractions of the upright
  /// preview (top-left, top-right, bottom-right, bottom-left), or null.
  List<Offset>? _quad;

  /// Phone tilt from the accelerometer, for the level bubble.
  Offset _tilt = Offset.zero;
  StreamSubscription<AccelerometerEvent>? _level;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
    try {
      _level = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval).listen((e) {
        final t = Offset(e.x, -e.y);
        if (mounted && (t - _tilt).distance > 0.15) setState(() => _tilt = t);
      }, onError: (Object _) {});
    } catch (_) {
      // No accelerometer: no bubble.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _level?.cancel();
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
    final quad = _findPage(image);
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
    if (mounted) {
      setState(() {
        _detected = detected;
        _steady = steady;
        _quad = quad;
      });
    }
  }

  /// The page under the camera: the bright area around the centre on a
  /// coarse grid of the luminance plane, and its four outermost corners.
  /// Null when no page stands out or it fills the whole view.
  List<Offset>? _findPage(CameraImage image) {
    final plane = image.planes.first;
    final w = image.width, h = image.height, stride = plane.bytesPerRow;
    final step = (w > h ? w : h) ~/ 120;
    if (step < 1) return null;
    final gw = w ~/ step, gh = h ~/ step;
    final cells = List<int>.filled(gw * gh, 0);
    final histogram = List<int>.filled(256, 0);
    for (var gy = 0; gy < gh; gy++) {
      for (var gx = 0; gx < gw; gx++) {
        final i = gy * step * stride + gx * step;
        final v = i < plane.bytes.length ? plane.bytes[i] : 0;
        cells[gy * gw + gx] = v;
        histogram[v]++;
      }
    }
    // Otsu threshold between paper and background.
    final total = gw * gh;
    var sumAll = 0.0;
    for (var t = 0; t < 256; t++) {
      sumAll += t * histogram[t];
    }
    var sumB = 0.0, wB = 0, best = 0.0, threshold = 128;
    for (var t = 0; t < 256; t++) {
      wB += histogram[t];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += t * histogram[t];
      final mB = sumB / wB, mF = (sumAll - sumB) / wF;
      final between = wB * wF * (mB - mF) * (mB - mF);
      if (between > best) {
        best = between;
        threshold = t;
      }
    }
    // Grow the bright area from the centre.
    var start = -1;
    for (var r = 0; r < 6 && start < 0; r++) {
      for (final (dx, dy) in [(0, 0), (r, 0), (-r, 0), (0, r), (0, -r)]) {
        final i = (gh ~/ 2 + dy) * gw + gw ~/ 2 + dx;
        if (cells[i] > threshold) {
          start = i;
          break;
        }
      }
    }
    if (start < 0) return null;
    final seen = List<bool>.filled(total, false);
    seen[start] = true;
    final queue = [start];
    var minS = 1 << 30, maxS = -1, minD = 1 << 30, maxD = -(1 << 30);
    var tl = start, br = start, tr = start, bl = start, edges = 0;
    for (var k = 0; k < queue.length; k++) {
      final i = queue[k];
      final x = i % gw, y = i ~/ gw;
      if (x == 0 || y == 0 || x == gw - 1 || y == gh - 1) edges++;
      if (x + y < minS) {
        minS = x + y;
        tl = i;
      }
      if (x + y > maxS) {
        maxS = x + y;
        br = i;
      }
      if (x - y > maxD) {
        maxD = x - y;
        tr = i;
      }
      if (x - y < minD) {
        minD = x - y;
        bl = i;
      }
      for (final j in [if (x > 0) i - 1, if (x < gw - 1) i + 1, if (y > 0) i - gw, if (y < gh - 1) i + gw]) {
        if (!seen[j] && cells[j] > threshold) {
          seen[j] = true;
          queue.add(j);
        }
      }
    }
    // Too small to be the page, or running off every side (no edges to show).
    if (queue.length < total * 0.12 || edges > (gw + gh) * 1.2) return null;
    final turn = _controller?.description.sensorOrientation ?? 90;
    Offset upright(int i) {
      final u = (i % gw + 0.5) / gw, v = (i ~/ gw + 0.5) / gh;
      return turn == 270 ? Offset(v, 1 - u) : Offset(1 - v, u);
    }

    // Sensor corners turned upright, then ordered by their upright position.
    final pts = [tl, tr, br, bl].map(upright).toList();
    pts.sort((a, b) => (a.dx + a.dy).compareTo(b.dx + b.dy));
    final topLeft = pts.first, bottomRight = pts.last;
    final rest = [pts[1], pts[2]]..sort((a, b) => (b.dx - b.dy).compareTo(a.dx - a.dy));
    return [topLeft, rest.first, bottomRight, rest.last];
  }

  /// The found page as a crop for the photo, with a margin so no text is cut.
  List<double>? _cropFrame() {
    final q = _quad;
    if (q == null) return null;
    const pad = 0.03;
    final xs = q.map((p) => p.dx), ys = q.map((p) => p.dy);
    final f = [
      (xs.reduce((a, b) => a < b ? a : b) - pad).clamp(0.0, 1.0),
      (ys.reduce((a, b) => a < b ? a : b) - pad).clamp(0.0, 1.0),
      (xs.reduce((a, b) => a > b ? a : b) + pad).clamp(0.0, 1.0),
      (ys.reduce((a, b) => a > b ? a : b) + pad).clamp(0.0, 1.0),
    ];
    // Nearly the whole photo: nothing to leave out.
    return (f[2] - f[0]) * (f[3] - f[1]) > 0.9 ? null : f;
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || _busy || !c.value.isInitialized) return;
    setState(() => _busy = true);
    try {
      final frame = _cropFrame();
      await _stopStream();
      final file = await c.takePicture();
      _shots.add(file.path);
      if (frame != null) CameraPage._frames[file.path] = frame;
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
            'Om du tidigare har nekat: öppna telefonens Inställningar → Appar → Bokföring → Behörigheter och tillåt Kamera.',
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
                        // The page outline is drawn on the preview itself, so it
                        // is cropped and scaled exactly like the picture.
                        child: Stack(fit: StackFit.expand, children: [
                          CameraPreview(c),
                          if (_quad != null) CustomPaint(painter: _PagePainter(_quad!)),
                        ]),
                      ),
                    ),
                    CustomPaint(painter: _FramePainter(_detected)),
                    Positioned(right: 14, bottom: 14, child: _LevelBubble(_tilt)),
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

/// Yellow outline of the page the camera sees, so the user can tell it from
/// papers underneath before taking the photo.
class _PagePainter extends CustomPainter {
  final List<Offset> quad;
  const _PagePainter(this.quad);

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [for (final p in quad) Offset(p.dx * size.width, p.dy * size.height)];
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(path, Paint()..color = const Color(0x33FFD600));
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFFFD600)
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.shortestSide / 110
          ..strokeJoin = StrokeJoin.round);
    for (final p in pts) {
      canvas.drawCircle(p, size.shortestSide / 45, Paint()..color = const Color(0xFFFFD600));
    }
  }

  @override
  bool shouldRepaint(_PagePainter old) => old.quad != quad;
}

/// A spirit level: the bubble sits in the middle ring when the phone is held
/// flat over the paper. Only a help; the photo can be taken any time.
class _LevelBubble extends StatelessWidget {
  final Offset tilt;
  const _LevelBubble(this.tilt);

  @override
  Widget build(BuildContext context) {
    const size = 64.0, bubble = 16.0;
    final level = tilt.distance < 0.8;
    // About 25 degrees of tilt moves the bubble to the edge.
    final d = tilt / 4.0;
    final off = d.distance > 1 ? d / d.distance : d;
    final color = level ? _accent : const Color(0xFFFFD600);
    return Semantics(
      label: level ? 'Telefonen hålls rakt' : 'Håll telefonen rakt över pappret',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.45),
          border: Border.all(color: Colors.white70, width: 1.5),
        ),
        child: Stack(alignment: Alignment.center, children: [
          Container(
            width: bubble + 8,
            height: bubble + 8,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white54)),
          ),
          Transform.translate(
            offset: off * ((size - bubble) / 2 - 2),
            child: Container(
              width: bubble,
              height: bubble,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
          ),
        ]),
      ),
    );
  }
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
