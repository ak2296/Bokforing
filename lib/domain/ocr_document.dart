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
  List<List<OcrLine>> rows() {
    final ls = lines.where((l) => l.text.trim().isNotEmpty).toList()
      ..sort((a, b) => a.cy.compareTo(b.cy));
    final rows = <List<OcrLine>>[];
    var rowCy = 0.0, rowH = 0.0;
    for (final l in ls) {
      final limit = (rowH < l.h ? rowH : l.h) * 0.6;
      if (rows.isNotEmpty && (l.cy - rowCy).abs() <= limit) {
        rows.last.add(l);
        final n = rows.last.length;
        rowCy = (rowCy * (n - 1) + l.cy) / n;
        rowH = (rowH * (n - 1) + l.h) / n;
      } else {
        rows.add([l]);
        rowCy = l.cy;
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
