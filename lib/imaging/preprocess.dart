import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// The camera guide frame, as a fraction of the preview. The captured photo is
/// cropped with the same fractions, so "inside the frame" means what it says.
const kFrameInsetX = 0.06;
const kFrameInsetY = 0.08;

// Provisional thresholds, to be calibrated on real photos. Real photos so far:
// brightness 123-158 and sharpness 334-1417 (so these limits are conservative).
const _minBrightness = 70.0;
const _minSharpness = 60.0;
const _maxOcrWidth = 2200;

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
    required this.paperFound,
  });
  final Uint8List jpeg;
  final List<QualityIssue> issues;
  final double brightness, sharpness, skewDegrees;
  final bool paperFound;
}

Future<PreprocessResult> preprocessDocument(Uint8List bytes) =>
    compute(preprocessSync, bytes);

/// Orientation fix, crop to frame, crop to the paper, grayscale, deskew and
/// contrast stretch. Deliberately no binarisation or sharpening: those erase
/// decimal commas.
PreprocessResult preprocessSync(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw StateError('Bilden kunde inte läsas.');
  var im = img.bakeOrientation(decoded);
  final cx = (im.width * kFrameInsetX).round();
  final cy = (im.height * kFrameInsetY).round();
  im = img.copyCrop(im, x: cx, y: cy, width: im.width - 2 * cx, height: im.height - 2 * cy);
  img.grayscale(im);

  // Find the bright paper against a darker background and crop to it, so the
  // text keeps its resolution (a narrow receipt strip is otherwise tiny).
  var paperFound = false;
  final probe = img.copyResize(im, width: 480, interpolation: img.Interpolation.linear);
  final pg = _gray(probe);
  final box = _paperBox(pg, probe.width, probe.height, _otsu(pg));
  if (box != null) {
    final sx = im.width / probe.width, sy = im.height / probe.height;
    final mx = im.width * 0.01, my = im.height * 0.01;
    final x0 = math.max(0, (box[0] * sx - mx).round());
    final y0 = math.max(0, (box[1] * sy - my).round());
    final x1 = math.min(im.width, ((box[2] + 1) * sx + mx).round());
    final y1 = math.min(im.height, ((box[3] + 1) * sy + my).round());
    if (x1 - x0 > 50 && y1 - y0 > 50) {
      im = img.copyCrop(im, x: x0, y: y0, width: x1 - x0, height: y1 - y0);
      paperFound = true;
    }
  }
  if (im.width > _maxOcrWidth) {
    im = img.copyResize(im, width: _maxOcrWidth, interpolation: img.Interpolation.linear);
  }

  // Sharpness at full resolution on the centre of the document.
  final sw = math.min(im.width, 1000), sh = math.min(im.height, 1000);
  final sharp = _laplacianVariance(im, (im.width - sw) ~/ 2, (im.height - sh) ~/ 2, sw, sh);

  // Everything else is measured on a small copy.
  final small = img.copyResize(im, width: math.min(640, im.width),
      interpolation: img.Interpolation.linear);
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

  // Skew: sweep angles, pick the one with the sharpest text-row profile,
  // then verify on rotated copies so the rotation direction can't be wrong.
  var chosen = 0.0;
  final pts = _darkPoints(g, w, h, darkThr);
  if (pts.$1.length > 200) {
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
        final p = _darkPoints(_gray(r), r.width, r.height, darkThr);
        return _rowScore(p.$1, p.$2, 0, r.width, r.height);
      }

      final s0 = zeroScore(0), sp = zeroScore(mag), sn = zeroScore(-mag);
      if (sp > s0 * 1.03 && sp >= sn) {
        chosen = mag;
      } else if (sn > s0 * 1.03) {
        chosen = -mag;
      }
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
    paperFound: paperFound,
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

/// Otsu's method: the gray level that best separates paper from background.
int _otsu(Uint8List g) {
  final hist = List<int>.filled(256, 0);
  for (final v in g) {
    hist[v]++;
  }
  final total = g.length;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumB = 0.0, maxVar = 0.0;
  var wB = 0, best = 0;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB, mF = (sum - sumB) / wF;
    final v = wB.toDouble() * wF * (mB - mF) * (mB - mF);
    if (v > maxVar) {
      maxVar = v;
      best = t;
    }
  }
  return best;
}

/// Longest run of indices whose count is >= [minCount], tolerating small gaps.
List<int>? _longestRun(List<int> v, int minCount, int gap) {
  List<int>? best;
  var start = -1, last = -1;
  void close() {
    if (start >= 0 && (best == null || last - start > best![1] - best![0])) {
      best = [start, last];
    }
    start = -1;
  }

  for (var i = 0; i < v.length; i++) {
    if (v[i] >= minCount) {
      if (start < 0) start = i;
      last = i;
    } else if (start >= 0 && i - last > gap) {
      close();
    }
  }
  close();
  return best;
}

/// Bounding box [left, top, right, bottom] of the bright paper, or null.
List<int>? _paperBox(Uint8List g, int w, int h, int thr) {
  final col = List<int>.filled(w, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (g[y * w + x] > thr) col[x]++;
    }
  }
  final cr = _longestRun(col, (h * 0.5).round(), 3);
  if (cr == null) return null;
  final row = List<int>.filled(h, 0);
  for (var y = 0; y < h; y++) {
    for (var x = cr[0]; x <= cr[1]; x++) {
      if (g[y * w + x] > thr) row[y]++;
    }
  }
  final rr = _longestRun(row, ((cr[1] - cr[0] + 1) * 0.5).round(), 3);
  if (rr == null) return null;
  final area = (cr[1] - cr[0] + 1) * (rr[1] - rr[0] + 1);
  if (area < 0.12 * w * h) return null;
  return [cr[0], rr[0], cr[1], rr[1]];
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
