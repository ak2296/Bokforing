import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// The camera guide frame, as a fraction of the preview. The captured photo is
/// cropped with the same fractions, so "inside the frame" means what it says.
const kFrameInsetX = 0.06;
const kFrameInsetY = 0.08;

// Provisional thresholds. They must be calibrated on real photos of
// invoices and Z-reports; the quality screen shows the measured values.
const _minBrightness = 70.0;
const _minSharpness = 60.0;
const _maxOcrWidth = 1600;

class QualityIssue {
  const QualityIssue(this.code, this.message, this.hint, {this.blocking = false});
  final String code, message, hint;

  /// Blocking issues make OCR unreliable; the user must choose to proceed.
  final bool blocking;
}

class PreprocessResult {
  const PreprocessResult({
    required this.jpeg,
    required this.issues,
    required this.brightness,
    required this.sharpness,
    required this.skewDegrees,
  });
  final Uint8List jpeg;
  final List<QualityIssue> issues;
  final double brightness, sharpness, skewDegrees;
}

Future<PreprocessResult> preprocessDocument(Uint8List bytes) =>
    compute(preprocessSync, bytes);

/// Orientation fix, crop to frame, grayscale, deskew and contrast stretch.
/// Deliberately no binarisation or sharpening: those erase decimal commas.
PreprocessResult preprocessSync(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw StateError('Bilden kunde inte läsas.');
  var im = img.bakeOrientation(decoded);
  final cx = (im.width * kFrameInsetX).round();
  final cy = (im.height * kFrameInsetY).round();
  im = img.copyCrop(im, x: cx, y: cy, width: im.width - 2 * cx, height: im.height - 2 * cy);
  if (im.width > _maxOcrWidth) {
    im = img.copyResize(im, width: _maxOcrWidth, interpolation: img.Interpolation.linear);
  }
  img.grayscale(im);

  // Sharpness is measured at full resolution on the centre of the document.
  final sw = math.min(im.width, 1000), sh = math.min(im.height, 1000);
  final sharp = _laplacianVariance(im, (im.width - sw) ~/ 2, (im.height - sh) ~/ 2, sw, sh);

  // Everything else is measured on a small copy.
  final small = img.copyResize(im, width: 640, interpolation: img.Interpolation.linear);
  final w = small.width, h = small.height;
  final g = _gray(small);
  final hist = List<int>.filled(256, 0);
  var sum = 0;
  for (final v in g) {
    hist[v]++;
    sum += v;
  }
  final brightness = sum / g.length;
  int pct(double f) {
    final target = (g.length * f).round();
    var acc = 0;
    for (var i = 0; i < 256; i++) {
      acc += hist[i];
      if (acc >= target) return i;
    }
    return 255;
  }

  final lo = pct(0.02).toDouble();
  var hi = pct(0.98).toDouble();
  if (hi - lo < 20) hi = lo + 20;
  final darkThr = lo + (hi - lo) * 0.45;

  final issues = <QualityIssue>[];
  if (brightness < _minBrightness) {
    issues.add(const QualityIssue('dark', 'För mörk', 'Tänd belysningen eller använd ficklampan.',
        blocking: true));
  }
  if (sharp < _minSharpness) {
    issues.add(const QualityIssue(
        'blur', 'Texten är suddig', 'Håll telefonen stilla och låt kameran fokusera.',
        blocking: true));
  }
  if (_touchesEdges(g, w, h, darkThr)) {
    issues.add(const QualityIssue(
        'cutoff', 'Dokumentet syns inte helt', 'Se till att hela dokumentet ryms inom ramen.'));
  }

  // Skew: sweep angles, pick the one with the sharpest text-row profile,
  // then verify on rotated copies (so the rotation direction can't be wrong).
  var chosen = 0.0;
  final pts = _darkPoints(g, w, h, darkThr);
  var bestAngle = 0.0, bestScore = -1.0;
  for (var a = -8.0; a <= 8.0; a += 0.5) {
    final s = _rowScore(pts.$1, pts.$2, a, w, h);
    if (s > bestScore) {
      bestScore = s;
      bestAngle = a;
    }
  }
  final mag = bestAngle.abs();
  if (mag >= 7.5) {
    issues.add(const QualityIssue(
        'skew', 'Dokumentet är snett', 'Håll telefonen rakt ovanför dokumentet.'));
  }
  if (mag >= 0.75 && mag < 7.5) {
    double zeroScore(double deg) {
      final r = deg == 0
          ? small
          : img.copyRotate(small, angle: deg, interpolation: img.Interpolation.linear);
      final rg = _gray(r);
      final p = _darkPoints(rg, r.width, r.height, darkThr);
      return _rowScore(p.$1, p.$2, 0, r.width, r.height);
    }

    final s0 = zeroScore(0), sp = zeroScore(mag), sn = zeroScore(-mag);
    if (sp > s0 * 1.03 && sp >= sn) {
      chosen = mag;
    } else if (sn > s0 * 1.03) {
      chosen = -mag;
    }
  }
  if (chosen != 0) {
    im = img.copyRotate(im, angle: chosen, interpolation: img.Interpolation.linear);
  }

  // Linear contrast stretch from the 2nd to the 98th percentile.
  final range = hi - lo;
  for (final p in im) {
    final v = (((p.r - lo) * 255) / range).round().clamp(0, 255);
    p.r = v;
    p.g = v;
    p.b = v;
  }

  return PreprocessResult(
    jpeg: img.encodeJpg(im, quality: 92),
    issues: issues,
    brightness: brightness,
    sharpness: sharp,
    skewDegrees: chosen,
  );
}

Uint8List _gray(img.Image im) {
  final g = Uint8List(im.width * im.height);
  var i = 0;
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      g[i++] = im.getPixel(x, y).r.toInt();
    }
  }
  return g;
}

double _laplacianVariance(img.Image im, int x0, int y0, int w, int h) {
  if (w < 3 || h < 3) return 0;
  final g = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      g[y * w + x] = im.getPixel(x0 + x, y0 + y).r.toInt();
    }
  }
  var sum = 0.0, sumSq = 0.0;
  var n = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final l = 4 * g[i] - g[i - 1] - g[i + 1] - g[i - w] - g[i + w];
      sum += l;
      sumSq += l * l;
      n++;
    }
  }
  final mean = sum / n;
  return sumSq / n - mean * mean;
}

/// True if dark "ink" runs into the outer 2 % band on any side.
bool _touchesEdges(Uint8List g, int w, int h, double thr) {
  final bx = math.max(2, (w * 0.02).round()), by = math.max(2, (h * 0.02).round());
  double frac(int x0, int y0, int x1, int y1) {
    var dark = 0, n = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        n++;
        if (g[y * w + x] <= thr) dark++;
      }
    }
    return n == 0 ? 0 : dark / n;
  }

  const limit = 0.04;
  return frac(0, 0, w, by) > limit ||
      frac(0, h - by, w, h) > limit ||
      frac(0, 0, bx, h) > limit ||
      frac(w - bx, 0, w, h) > limit;
}

/// Dark pixels from the central 70 % (avoids black corners after rotation).
(List<int>, List<int>) _darkPoints(Uint8List g, int w, int h, double thr) {
  final x0 = (w * 0.15).round(), x1 = (w * 0.85).round();
  final y0 = (h * 0.15).round(), y1 = (h * 0.85).round();
  var count = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      if (g[y * w + x] <= thr) count++;
    }
  }
  final stride = math.max(1, count ~/ 30000);
  final xs = <int>[], ys = <int>[];
  var k = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      if (g[y * w + x] <= thr && (k++ % stride == 0)) {
        xs.add(x);
        ys.add(y);
      }
    }
  }
  return (xs, ys);
}

/// Sum of squared row counts after rotating the points by [deg]; text lines
/// that are horizontal give the highest value.
double _rowScore(List<int> xs, List<int> ys, double deg, int w, int h) {
  final t = deg * math.pi / 180;
  final s = math.sin(t), c = math.cos(t);
  final bins = List<int>.filled(h + 2 * w + 2, 0);
  for (var i = 0; i < xs.length; i++) {
    final yy = (ys[i] * c - xs[i] * s).round() + w;
    if (yy >= 0 && yy < bins.length) bins[yy]++;
  }
  var sq = 0.0;
  for (final b in bins) {
    sq += b * b;
  }
  return sq;
}
