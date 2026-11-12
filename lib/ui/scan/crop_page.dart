import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app_icons.dart';

const _yellow = Color(0xFFFFD600);
const _background = Color(0xFF0C1411);

/// "Justera hörnen": the photo with the four corners of the paper, which the
/// user drags onto the real corners. Returns the corners as fractions of the
/// photo (top-left, top-right, bottom-right, bottom-left, each x then y), or
/// null when the user wants to take the photo again.
class CropPage extends StatefulWidget {
  final String path;

  /// Corners found in the viewfinder, as fractions; null starts near the edges.
  final List<Offset>? initial;
  const CropPage({super.key, required this.path, this.initial});

  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> {
  static const _full = [Offset(0.03, 0.03), Offset(0.97, 0.03), Offset(0.97, 0.97), Offset(0.03, 0.97)];
  late List<Offset> _corners = _sane(widget.initial) ?? List.of(_full);
  Size? _imageSize;
  int? _dragging;
  Offset? _finger;

  /// A usable starting shape: four corners, not folded over each other.
  static List<Offset>? _sane(List<Offset>? q) {
    if (q == null || q.length != 4) return null;
    final c = [for (final p in q) Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0))];
    final area = _area(c);
    return area < 0.08 ? null : c;
  }

  static double _area(List<Offset> c) {
    var a = 0.0;
    for (var i = 0; i < 4; i++) {
      final p = c[i], q = c[(i + 1) % 4];
      a += p.dx * q.dy - q.dx * p.dy;
    }
    return a.abs() / 2;
  }

  @override
  void initState() {
    super.initState();
    final stream = FileImage(File(widget.path)).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      if (mounted) setState(() => _imageSize = Size(info.image.width.toDouble(), info.image.height.toDouble()));
      stream.removeListener(listener);
    });
    stream.addListener(listener);
  }

  Rect _imageRect(Size box) {
    final s = _imageSize!;
    final scale = (box.width / s.width) < (box.height / s.height) ? box.width / s.width : box.height / s.height;
    final w = s.width * scale, h = s.height * scale;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  void _done() {
    Navigator.pop(context, [for (final c in _corners) ...[c.dx, c.dy]]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        toolbarHeight: 44,
        titleTextStyle: const TextStyle(fontFamily: 'Inter', color: Colors.white, fontSize: 14),
        title: const Text('Justera hörnen'),
      ),
      body: SafeArea(
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Text('Dra de gula hörnen till dokumentets hörn. Det som ligger utanför ramen tas inte med.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Expanded(
            child: _imageSize == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(builder: (context, box) {
                    final rect = _imageRect(box.biggest);
                    Offset toScreen(Offset c) => Offset(rect.left + c.dx * rect.width, rect.top + c.dy * rect.height);
                    Offset toImage(Offset p) => Offset(
                        ((p.dx - rect.left) / rect.width).clamp(0.0, 1.0), ((p.dy - rect.top) / rect.height).clamp(0.0, 1.0));
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) {
                        var best = -1;
                        var bestDistance = 56.0;
                        for (var i = 0; i < 4; i++) {
                          final dist = (toScreen(_corners[i]) - d.localPosition).distance;
                          if (dist < bestDistance) {
                            best = i;
                            bestDistance = dist;
                          }
                        }
                        setState(() {
                          _dragging = best < 0 ? null : best;
                          _finger = d.localPosition;
                        });
                      },
                      onPanUpdate: (d) {
                        final i = _dragging;
                        if (i == null) return;
                        setState(() {
                          _corners[i] = toImage(d.localPosition);
                          _finger = d.localPosition;
                        });
                      },
                      onPanEnd: (_) => setState(() {
                        _dragging = null;
                        _finger = null;
                      }),
                      child: Stack(children: [
                        Positioned.fromRect(rect: rect, child: Image.file(File(widget.path), fit: BoxFit.fill)),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _CornerPainter([for (final c in _corners) toScreen(c)], _dragging),
                          ),
                        ),
                        // A magnifier above the finger, so the corner can be placed exactly.
                        if (_finger != null && _dragging != null)
                          Positioned(
                            left: _finger!.dx - 55,
                            top: _finger!.dy - 170,
                            child: const RawMagnifier(
                              size: Size(110, 110),
                              magnificationScale: 2.2,
                              focalPointOffset: Offset(0, 115),
                              decoration: MagnifierDecoration(
                                shape: CircleBorder(side: BorderSide(color: _yellow, width: 3)),
                              ),
                            ),
                          ),
                      ]),
                    );
                  }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
            child: Row(children: [
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const Icon(AppIcons.camera, size: 18),
                  label: const Text('Ta om'),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const Icon(AppIcons.image, size: 18),
                  label: const Text('Hela bilden'),
                  onPressed: () => setState(() => _corners = List.of(_full)),
                ),
              ),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF5FE0B0), foregroundColor: _background),
                  icon: const Icon(AppIcons.check, size: 18),
                  label: const Text('Klar'),
                  onPressed: _done,
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final List<Offset> corners;
  final int? active;
  const _CornerPainter(this.corners, this.active);

  @override
  void paint(Canvas canvas, Size size) {
    final quad = Path()..addPolygon(corners, true);
    // Darken everything outside the paper.
    canvas.drawPath(
      Path.combine(ui.PathOperation.difference, Path()..addRect(Offset.zero & size), quad),
      Paint()..color = Colors.black.withValues(alpha: 0.5),
    );
    canvas.drawPath(
      quad,
      Paint()
        ..color = _yellow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < corners.length; i++) {
      canvas.drawCircle(corners[i], i == active ? 16 : 13, Paint()..color = _yellow.withValues(alpha: 0.35));
      canvas.drawCircle(corners[i], 8, Paint()..color = _yellow);
    }
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.corners != corners || old.active != active;
}
