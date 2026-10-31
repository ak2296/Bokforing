/// OCR result without any dependency on ML Kit, so the layout logic is testable.
class OcrLine {
  const OcrLine(this.text, this.left, this.top, this.right, this.bottom);
  final String text;
  final double left, top, right, bottom;

  double get cy => (top + bottom) / 2;
  double get h => bottom - top;
}

class OcrDocument {
  const OcrDocument(this.fullText, this.lines);

  /// Raw text exactly as the recognizer returned it.
  final String fullText;

  /// All recognised lines with bounding boxes (pixels in the scanned image).
  final List<OcrLine> lines;

  /// Receipts and Z-reports are tables: a label and its amount are often
  /// returned as separate lines. Group lines that share a vertical position
  /// into rows so "Totalt" and "1 250,00" end up on the same text row.
  /// Tilt of the text rows (dy/dx), from the median slope between each line
  /// and the nearest line to its right on roughly the same row. A page photo
  /// tilted by 1-2 degrees otherwise puts amounts a few pixels lower than their
  /// labels, and they end up on separate rows.
  double _slope() {
    final ls = lines.where((l) => l.text.trim().isNotEmpty).toList();
    final slopes = <double>[];
    for (final a in ls) {
      OcrLine? best;
      for (final b in ls) {
        if (identical(a, b) || b.left - a.left < 150) continue;
        if ((b.cy - a.cy).abs() > a.h * 0.8) continue;
        if (best == null || b.left < best.left) best = b;
      }
      if (best != null) {
        final dx = (best.left + best.right) / 2 - (a.left + a.right) / 2;
        if (dx > 50) slopes.add((best.cy - a.cy) / dx);
      }
    }
    if (slopes.length < 5) return 0;
    slopes.sort();
    final m = slopes[slopes.length ~/ 2];
    return m.abs() <= 0.12 ? m : 0;
  }

  List<List<OcrLine>> rows() {
    final k = _slope();
    double y(OcrLine l) => l.cy - k * (l.left + l.right) / 2;
    final ls = lines.where((l) => l.text.trim().isNotEmpty).toList()
      ..sort((a, b) => y(a).compareTo(y(b)));
    final rows = <List<OcrLine>>[];
    var rowCy = 0.0, rowH = 0.0;
    for (final l in ls) {
      final limit = (rowH < l.h ? rowH : l.h) * 0.6;
      if (rows.isNotEmpty && (y(l) - rowCy).abs() <= limit) {
        rows.last.add(l);
        final n = rows.last.length;
        rowCy = (rowCy * (n - 1) + y(l)) / n;
        rowH = (rowH * (n - 1) + l.h) / n;
      } else {
        rows.add([l]);
        rowCy = y(l);
        rowH = l.h;
      }
    }
    for (final r in rows) {
      r.sort((a, b) => a.left.compareTo(b.left));
    }
    return rows;
  }

  /// Text with one table row per line; large gaps become two spaces.
  String toText() => rows().map(_join).join('\n');

  static String _join(List<OcrLine> row) {
    final b = StringBuffer();
    for (var i = 0; i < row.length; i++) {
      if (i > 0) {
        final gap = row[i].left - row[i - 1].right;
        b.write(gap > row[i].h * 2 ? '  ' : ' ');
      }
      b.write(row[i].text.replaceAll('\n', ' ').trim());
    }
    return b.toString();
  }
}
