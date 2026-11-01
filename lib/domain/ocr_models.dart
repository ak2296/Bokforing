import 'dart:convert';
import 'dart:math' as math;

/// Rectangle in image pixels.
class OcrBox {
  final double left, top, right, bottom;
  const OcrBox(this.left, this.top, this.right, this.bottom);

  double get height => bottom - top;
  double get centerY => (top + bottom) / 2;

  List<double> toJson() => [left, top, right, bottom];
  factory OcrBox.fromJson(List<dynamic> j) => OcrBox(
      (j[0] as num).toDouble(), (j[1] as num).toDouble(), (j[2] as num).toDouble(), (j[3] as num).toDouble());
}

class OcrElement {
  final String text;
  final OcrBox box;
  final double? confidence;
  const OcrElement(this.text, this.box, {this.confidence});

  Map<String, dynamic> toJson() => {'t': text, 'b': box.toJson(), if (confidence != null) 'c': confidence};
  factory OcrElement.fromJson(Map<String, dynamic> j) => OcrElement(
      j['t'] as String, OcrBox.fromJson(j['b'] as List), confidence: (j['c'] as num?)?.toDouble());
}

class OcrLine {
  final String text;
  final OcrBox box;
  final List<OcrElement> words;
  final double? confidence;

  /// Rotation of the line in degrees as reported by ML Kit.
  final double? angle;
  const OcrLine(this.text, this.box, {this.words = const [], this.confidence, this.angle});

  Map<String, dynamic> toJson() => {
        't': text,
        'b': box.toJson(),
        if (confidence != null) 'c': confidence,
        if (angle != null) 'a': angle,
        'w': [for (final w in words) w.toJson()],
      };
  factory OcrLine.fromJson(Map<String, dynamic> j) => OcrLine(
        j['t'] as String,
        OcrBox.fromJson(j['b'] as List),
        confidence: (j['c'] as num?)?.toDouble(),
        angle: (j['a'] as num?)?.toDouble(),
        words: [for (final w in (j['w'] as List? ?? const [])) OcrElement.fromJson(w as Map<String, dynamic>)],
      );
}

class OcrBlock {
  final String text;
  final OcrBox box;
  final List<OcrLine> lines;
  const OcrBlock(this.text, this.box, this.lines);

  Map<String, dynamic> toJson() =>
      {'t': text, 'b': box.toJson(), 'l': [for (final l in lines) l.toJson()]};
  factory OcrBlock.fromJson(Map<String, dynamic> j) => OcrBlock(
        j['t'] as String,
        OcrBox.fromJson(j['b'] as List),
        [for (final l in j['l'] as List) OcrLine.fromJson(l as Map<String, dynamic>)],
      );
}

/// A visual row on the page: OCR lines whose vertical centres line up,
/// ordered left to right. Labels and their amounts often arrive as separate
/// OCR lines, so extraction works on rows rather than raw lines.
class TextRow {
  final String text;
  final OcrBox box;
  final int index;
  const TextRow(this.text, this.box, this.index);
}

/// Everything the OCR engine returned, preserved so extraction and the user
/// can refer back to the original text and positions.
class OcrResult {
  final String text;
  final List<OcrBlock> blocks;
  final int imageWidth;
  final int imageHeight;

  const OcrResult({required this.text, required this.blocks, this.imageWidth = 0, this.imageHeight = 0});

  /// Builds a result from plain text (manual paste, tests, AI output). Each
  /// line becomes its own row.
  factory OcrResult.fromPlainText(String text) {
    final lines = <OcrLine>[];
    final raw = text.split(RegExp(r'\r?\n'));
    for (var i = 0; i < raw.length; i++) {
      final t = raw[i].trimRight();
      if (t.trim().isEmpty) continue;
      final box = OcrBox(0, i * 20.0, t.length * 10.0, i * 20.0 + 16);
      lines.add(OcrLine(t, box));
    }
    return OcrResult(
      text: text,
      blocks: [for (final l in lines) OcrBlock(l.text, l.box, [l])],
      imageWidth: 1000,
      imageHeight: raw.length * 20,
    );
  }

  List<OcrLine> get lines => [for (final b in blocks) ...b.lines];

  /// Mean confidence of all lines that report one (ML Kit may not).
  double? get meanConfidence {
    final c = lines.map((l) => l.confidence).whereType<double>().toList();
    if (c.isEmpty) return null;
    return c.reduce((a, b) => a + b) / c.length;
  }

  /// Text printed sideways along the paper edge ("EJ KVITTO PÅ KÖP", print
  /// timestamps) shows up as tall, narrow lines. It is never accounting data.
  bool isMarginText(OcrLine l) {
    final t = l.text.trim();
    if (t.length < 3) return false;
    final w = l.box.right - l.box.left;
    return l.box.height > 2.5 * w;
  }

  /// Groups lines into visual rows. On a slightly tilted photo a label at
  /// the left and its amount at the right end up at different heights, so
  /// the heights are corrected for the page tilt first. The tilt comes from
  /// ML Kit's line angles; since its sign convention is not documented, both
  /// directions (and no correction) are tried and the one that pairs the
  /// most lines wins.
  ///
  /// On a curved page the amount column can sit a whole line off from its
  /// names: [rightShift] moves amount-only lines at the right by that many
  /// pixels before grouping (see [rowShifts]).
  List<TextRow> rows({double rightShift = 0}) {
    final kept = lines.where((l) => !isMarginText(l)).toList();
    final angles = kept.map((l) => l.angle).whereType<double>().where((a) => a.abs() < 15).toList()..sort();
    final median = angles.isEmpty ? 0.0 : angles[angles.length ~/ 2];
    final candidates = median.abs() < 0.2 ? [0.0] : [0.0, median, -median];
    List<List<OcrLine>>? best;
    for (final deg in candidates) {
      final g = _group(kept, math.tan(deg * math.pi / 180), rightShift);
      if (best == null || g.length < best.length) best = g;
    }
    final groups = best ?? const <List<OcrLine>>[];
    final rows = <TextRow>[];
    for (final g in groups) {
      g.sort((a, b) => a.box.left.compareTo(b.box.left));
      final box = OcrBox(
        g.map((l) => l.box.left).reduce((a, b) => a < b ? a : b),
        g.map((l) => l.box.top).reduce((a, b) => a < b ? a : b),
        g.map((l) => l.box.right).reduce((a, b) => a > b ? a : b),
        g.map((l) => l.box.bottom).reduce((a, b) => a > b ? a : b),
      );
      rows.add(TextRow(cleanOcrText(g.map((l) => l.text.trim()).join('   ')), box, rows.length));
    }
    return rows;
  }

  /// Repairs a common OCR slip on receipts: a space next to the decimal
  /// comma ("598, 90" or "598 ,90" for 598,90), which would otherwise be read
  /// as two numbers.
  ///
  /// A "|" between digits is a misread 1 ("43|1,30").
  static String cleanOcrText(String s) =>
      s
          // The letter O for zero after a decimal comma: "198, OO".
          .replaceAllMapped(RegExp(r'(\d[,.]\s?)[Oo]{2}\b'), (m) => '${m[1]}00')
          .replaceAllMapped(RegExp(r'(?<=\d)\|(?=[\d,])'), (m) => '1')
          .replaceAllMapped(RegExp(r'(\d)\s?([,.])\s(\d{2})(?![\d,.])'), (m) => '${m[1]}${m[2]}${m[3]}')
          .replaceAllMapped(
          RegExp(r'(\d)\s([,.])(\d{2})(?![\d,.])'), (m) => '${m[1]}${m[2]}${m[3]}');

  static bool _isAmountOnly(String text) {
    final t = text.replaceAll(RegExp(r'\b(kr|sek)\b', caseSensitive: false), '');
    return RegExp(r'\d').hasMatch(t) && !RegExp(r'[A-Za-zÅÄÖåäö]{2,}').hasMatch(t);
  }

  bool _isRightAmount(OcrLine l, double pageRight) =>
      _isAmountOnly(l.text) && (l.box.left + l.box.right) / 2 > pageRight / 2;

  /// Offsets worth trying for [rows]: up to two lines each way. Empty when
  /// the page has no separate amount column.
  List<double> rowShifts() {
    final kept = lines.where((l) => !isMarginText(l)).toList();
    if (kept.isEmpty) return const [];
    final pageRight = kept.map((l) => l.box.right).reduce(math.max);
    if (!kept.any((l) => _isRightAmount(l, pageRight))) return const [];
    final heights = kept.map((l) => l.box.height).toList()..sort();
    final h = heights[heights.length ~/ 2];
    if (h <= 0) return const [];
    return [for (final f in const [1.0, -1.0, 0.5, -0.5, 1.5, -1.5, 2.0, -2.0]) f * h];
  }

  List<List<OcrLine>> _group(List<OcrLine> kept, double slope, double rightShift) {
    final midX = kept.isEmpty ? 0.0 : kept.map((l) => (l.box.left + l.box.right) / 2).reduce((a, b) => a + b) / kept.length;
    final pageRight = kept.isEmpty ? 0.0 : kept.map((l) => l.box.right).reduce(math.max);
    double y(OcrLine l) =>
        l.box.centerY -
        slope * ((l.box.left + l.box.right) / 2 - midX) -
        (rightShift != 0 && _isRightAmount(l, pageRight) ? rightShift : 0);
    final sorted = [...kept]..sort((a, b) => y(a).compareTo(y(b)));
    final groups = <List<OcrLine>>[];
    for (final line in sorted) {
      final h = line.box.height <= 0 ? 10.0 : line.box.height;
      List<OcrLine>? target;
      for (final g in groups.reversed.take(3)) {
        final last = g.last;
        final lh = last.box.height <= 0 ? 10.0 : last.box.height;
        final overlap = (y(line) - y(last)).abs() < 0.55 * (h < lh ? h : lh);
        final sideBySide = g.every((m) => line.box.left >= m.box.right - 2 || line.box.right <= m.box.left + 2);
        if (overlap && sideBySide) {
          target = g;
          break;
        }
      }
      if (target != null) {
        target.add(line);
      } else {
        groups.add([line]);
      }
    }
    return groups;
  }

  String toJsonString() => jsonEncode({
        'w': imageWidth,
        'h': imageHeight,
        'blocks': [for (final b in blocks) b.toJson()],
      });

  factory OcrResult.fromJsonString(String s, {required String text}) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    return OcrResult(
      text: text,
      imageWidth: j['w'] as int,
      imageHeight: j['h'] as int,
      blocks: [for (final b in j['blocks'] as List) OcrBlock.fromJson(b as Map<String, dynamic>)],
    );
  }
}
