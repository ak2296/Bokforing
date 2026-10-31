import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Problems found in a photo. Messages are shown to the user as-is.
enum QualityIssue { tooDark, tooBright, blurry, skewed, notFound }

extension QualityIssueText on QualityIssue {
  String get title => switch (this) {
        QualityIssue.tooDark => 'För mörk',
        QualityIssue.tooBright => 'För ljus eller reflexer',
        QualityIssue.blurry => 'Texten är suddig',
        QualityIssue.skewed => 'Dokumentet är snett',
        QualityIssue.notFound => 'Dokumentet syns inte helt',
      };

  String get advice => switch (this) {
        QualityIssue.tooDark => 'Tänd en lampa eller gå närmare ett fönster.',
        QualityIssue.tooBright => 'Undvik direkt ljus som blänker i papperet.',
        QualityIssue.blurry => 'Håll telefonen stilla och vänta tills bilden är skarp.',
        QualityIssue.skewed => 'Håll telefonen rakt ovanför dokumentet.',
        QualityIssue.notFound => 'Lägg dokumentet på en mörkare yta och få med hela dokumentet i ramen.',
      };
}

class QualityReport {
  final double brightness;
  final double sharpness;
  final double skewDegrees;
  final bool paperFound;
  final List<QualityIssue> issues;

  /// Height / width of the paper when its edges were found inside the photo
  /// (null when the paper filled the frame, so its shape is unknown).
  final double? paperAspect;
  const QualityReport(this.brightness, this.sharpness, this.skewDegrees, this.paperFound, this.issues,
      {this.paperAspect});

  bool get acceptable => issues.isEmpty;
}

class PreprocessResult {
  final Uint8List jpeg;
  final int width;
  final int height;
  final QualityReport quality;
  const PreprocessResult(this.jpeg, this.width, this.height, this.quality);
}

/// Input for [preprocessDocument]; plain data so it can run in an isolate.
class PreprocessRequest {
  final Uint8List bytes;

  /// Guide frame as fractions of the image (left, top, right, bottom), or
  /// null to use the whole photo.
  final List<double>? frame;
  const PreprocessRequest(this.bytes, {this.frame});
}

/// Thresholds are provisional. The owner's real photos measured brightness
/// 123–158 and sharpness 334–1417 with this method.
const minBrightness = 70.0;
const maxBrightness = 235.0;
const minSharpness = 60.0;
const maxCorrectableSkew = 10.0;

/// Prepares a document photo for OCR: orientation, crop to the guide frame
/// and the paper, deskew, shadow reduction and contrast. It deliberately
/// does not binarise or sharpen, which can erase decimal commas.
PreprocessResult preprocessDocument(PreprocessRequest req) {
  var image = img.decodeImage(req.bytes);
  if (image == null) throw const FormatException('Bilden kunde inte läsas.');
  image = img.bakeOrientation(image);

  final f = req.frame;
  if (f != null) {
    final x = (f[0] * image.width).round().clamp(0, image.width - 1);
    final y = (f[1] * image.height).round().clamp(0, image.height - 1);
    final w = ((f[2] - f[0]) * image.width).round().clamp(1, image.width - x);
    final h = ((f[3] - f[1]) * image.height).round().clamp(1, image.height - y);
    image = img.copyCrop(image, x: x, y: y, width: w, height: h);
  }

  // Resolution: keep small print readable without huge files.
  const maxSide = 2800;
  if (math.max(image.width, image.height) > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
  }

  var gray = _luminance(image);

  // Paper detection on a small copy: Otsu threshold, then the bounding box of
  // rows/columns that are mostly bright.
  final small = _downscale(gray, image.width, image.height, 400);
  final threshold = _otsu(small.data);
  final paper = _paperBox(small, threshold);
  var paperFound = paper != null;
  double? paperAspect;
  if (paper != null) {
    final sx = image.width / small.width;
    final sy = image.height / small.height;
    final pad = (0.01 * math.max(image.width, image.height)).round();
    final x0 = (paper[0] * sx).round() - pad;
    final y0 = (paper[1] * sy).round() - pad;
    final x1 = (paper[2] * sx).round() + pad;
    final y1 = (paper[3] * sy).round() + pad;
    final cx = x0.clamp(0, image.width - 1);
    final cy = y0.clamp(0, image.height - 1);
    final cw = (x1.clamp(cx + 1, image.width) - cx);
    final ch = (y1.clamp(cy + 1, image.height) - cy);
    if (cw * ch < image.width * image.height * 0.97) {
      paperAspect = ch / cw;
      image = img.copyCrop(image, x: cx, y: cy, width: cw, height: ch);
      gray = _luminance(image);
    }
  }

  final brightness = _mean(gray.data);
  final sharpness = _laplacianVariance(_downscale(gray, image.width, image.height, 1000));
  final skew = _estimateSkew(_downscale(gray, image.width, image.height, 500), threshold);

  if (skew.abs() >= 0.3 && skew.abs() <= maxCorrectableSkew) {
    image = img.copyRotate(image, angle: -skew, interpolation: img.Interpolation.linear);
    gray = _luminance(image);
  }

  final issues = <QualityIssue>[
    if (brightness < minBrightness) QualityIssue.tooDark,
    if (brightness > maxBrightness) QualityIssue.tooBright,
    if (sharpness < minSharpness) QualityIssue.blurry,
    if (skew.abs() > maxCorrectableSkew) QualityIssue.skewed,
    if (!paperFound) QualityIssue.notFound,
  ];
  if (paper != null) {
    // A paper region that is tiny means the document is far away.
    final area = (paper[2] - paper[0]) * (paper[3] - paper[1]);
    if (area < small.width * small.height * 0.12) {
      paperFound = false;
      issues.add(QualityIssue.notFound);
    }
  }

  final enhanced = _enhance(gray, image.width, image.height);
  final out = img.Image(width: image.width, height: image.height, numChannels: 1);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final v = enhanced[y * image.width + x];
      out.setPixelRgb(x, y, v, v, v);
    }
  }
  final jpeg = img.encodeJpg(out, quality: 92);
  return PreprocessResult(jpeg, image.width, image.height,
      QualityReport(brightness, sharpness, skew, paperFound, issues, paperAspect: paperAspect));
}

class _Gray {
  final Uint8List data;
  final int width;
  final int height;
  const _Gray(this.data, this.width, this.height);
}

_Gray _luminance(img.Image image) {
  final data = Uint8List(image.width * image.height);
  var i = 0;
  for (final p in image) {
    data[i++] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
  }
  return _Gray(data, image.width, image.height);
}

_Gray _downscale(_Gray g, int w, int h, int targetWidth) {
  if (w <= targetWidth) return g;
  final scale = w / targetWidth;
  final tw = targetWidth;
  final th = math.max(1, (h / scale).round());
  final out = Uint8List(tw * th);
  for (var y = 0; y < th; y++) {
    final y0 = (y * scale).floor();
    final y1 = math.min(h, ((y + 1) * scale).ceil());
    for (var x = 0; x < tw; x++) {
      final x0 = (x * scale).floor();
      final x1 = math.min(w, ((x + 1) * scale).ceil());
      var sum = 0;
      var n = 0;
      for (var yy = y0; yy < y1; yy++) {
        for (var xx = x0; xx < x1; xx++) {
          sum += g.data[yy * w + xx];
          n++;
        }
      }
      out[y * tw + x] = n == 0 ? 0 : sum ~/ n;
    }
  }
  return _Gray(out, tw, th);
}

double _mean(Uint8List d) {
  if (d.isEmpty) return 0;
  var s = 0;
  for (final v in d) {
    s += v;
  }
  return s / d.length;
}

int _otsu(Uint8List d) {
  final hist = List<int>.filled(256, 0);
  for (final v in d) {
    hist[v]++;
  }
  final total = d.length;
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumB = 0.0, wB = 0, best = 0.0, threshold = 127;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB;
    final mF = (sum - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      threshold = t;
    }
  }
  return threshold;
}

/// Bounding box (x0, y0, x1, y1) of the bright paper, or null when no clear
/// bright region exists.
List<int>? _paperBox(_Gray g, int threshold) {
  final w = g.width, h = g.height;
  bool brightRow(int y) {
    var n = 0;
    for (var x = 0; x < w; x++) {
      if (g.data[y * w + x] > threshold) n++;
    }
    return n > w * 0.35;
  }

  bool brightCol(int x, int y0, int y1) {
    var n = 0;
    for (var y = y0; y < y1; y++) {
      if (g.data[y * w + x] > threshold) n++;
    }
    return n > (y1 - y0) * 0.35;
  }

  var y0 = 0;
  while (y0 < h && !brightRow(y0)) {
    y0++;
  }
  var y1 = h - 1;
  while (y1 > y0 && !brightRow(y1)) {
    y1--;
  }
  if (y1 - y0 < h * 0.1) return null;
  var x0 = 0;
  while (x0 < w && !brightCol(x0, y0, y1)) {
    x0++;
  }
  var x1 = w - 1;
  while (x1 > x0 && !brightCol(x1, y0, y1)) {
    x1--;
  }
  if (x1 - x0 < w * 0.1) return null;
  return [x0, y0, x1 + 1, y1 + 1];
}

double _laplacianVariance(_Gray g) {
  final w = g.width, h = g.height;
  if (w < 3 || h < 3) return 0;
  var sum = 0.0, sumSq = 0.0;
  var n = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final l = 4 * g.data[i] - g.data[i - 1] - g.data[i + 1] - g.data[i - w] - g.data[i + w];
      sum += l;
      sumSq += l * l;
      n++;
    }
  }
  final mean = sum / n;
  return sumSq / n - mean * mean;
}

/// Text lines give sharp peaks in the row profile when the page is level.
/// Tries angles in ±12° and returns the one with the sharpest profile.
/// Only dark pixels next to bright paper count, so a dark table or the
/// corners around a tilted page do not dominate.
double _estimateSkew(_Gray g, int threshold) {
  final w = g.width, h = g.height;
  final dark = <(int, int)>[];
  const d = 3;
  bool bright(int x, int y) => x >= 0 && y >= 0 && x < w && y < h && g.data[y * w + x] > threshold;
  for (var y = 0; y < h; y += 2) {
    for (var x = 0; x < w; x += 2) {
      if (g.data[y * w + x] >= threshold - 30) continue;
      final nearPaper = bright(x - d, y) || bright(x + d, y) || bright(x, y - d) || bright(x, y + d);
      final insidePaper =
          (bright(x - 4 * d, y) && bright(x + 4 * d, y)) || (bright(x, y - 4 * d) && bright(x, y + 4 * d));
      if (nearPaper && insidePaper) dark.add((x, y));
    }
  }
  if (dark.length < 200) return 0;
  double score(double deg) {
    final t = math.tan(deg * math.pi / 180);
    final bins = List<int>.filled(h * 2, 0);
    for (final (x, y) in dark) {
      final yy = (y - (x - w / 2) * t).round() + h ~/ 2;
      if (yy >= 0 && yy < bins.length) bins[yy]++;
    }
    var s = 0.0;
    for (final b in bins) {
      s += b * b;
    }
    return s;
  }

  var best = 0.0, bestScore = score(0);
  for (var deg = -12.0; deg <= 12.0; deg += 0.5) {
    final s = score(deg);
    if (s > bestScore * 1.02) {
      bestScore = s;
      best = deg;
    }
  }
  // Refine around the best coarse angle.
  for (var deg = best - 0.4; deg <= best + 0.4; deg += 0.1) {
    final s = score(deg);
    if (s > bestScore) {
      bestScore = s;
      best = deg;
    }
  }
  return double.parse(best.toStringAsFixed(1));
}

/// Shadow reduction (divide by a blurred background estimate), then a
/// gentle percentile contrast stretch.
Uint8List _enhance(_Gray g, int w, int h) {
  // Background: downscale strongly, blur, then sample back per pixel.
  const bgWidth = 64;
  final bg = _boxBlur(_downscale(g, w, h, math.min(bgWidth, w)), 2);
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final by = (y * bg.height / h).floor().clamp(0, bg.height - 1);
    for (var x = 0; x < w; x++) {
      final bx = (x * bg.width / w).floor().clamp(0, bg.width - 1);
      final b = math.max(40, bg.data[by * bg.width + bx]);
      final v = g.data[y * w + x] * 235 / b;
      out[y * w + x] = v.round().clamp(0, 255);
    }
  }
  final hist = List<int>.filled(256, 0);
  for (final v in out) {
    hist[v]++;
  }
  int percentile(double p) {
    final target = out.length * p;
    var acc = 0;
    for (var i = 0; i < 256; i++) {
      acc += hist[i];
      if (acc >= target) return i;
    }
    return 255;
  }

  final lo = percentile(0.01);
  final hi = math.max(lo + 1, percentile(0.99));
  for (var i = 0; i < out.length; i++) {
    out[i] = ((out[i] - lo) * 255 / (hi - lo)).round().clamp(0, 255);
  }
  return out;
}

_Gray _boxBlur(_Gray g, int r) {
  final w = g.width, h = g.height;
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var s = 0, n = 0;
      for (var yy = math.max(0, y - r); yy <= math.min(h - 1, y + r); yy++) {
        for (var xx = math.max(0, x - r); xx <= math.min(w - 1, x + r); xx++) {
          s += g.data[yy * w + xx];
          n++;
        }
      }
      out[y * w + x] = s ~/ n;
    }
  }
  return _Gray(out, w, h);
}
