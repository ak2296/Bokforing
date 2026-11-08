import 'money.dart';
import 'text_patterns.dart';

/// A field the app can learn per supplier.
enum HintField {
  total('Summa'),
  vat('Moms'),
  number('Fakturanummer'),
  ocr('OCR-nummer'),
  date('Datum'),
  due('Förfallodatum');

  final String label;
  const HintField(this.label);

  static HintField? byName(String name) {
    for (final f in values) {
      if (f.name == name) return f;
    }
    return null;
  }
}

/// What the app learned from a correction: on this supplier's papers, the
/// value of [field] is printed after [label].
class SupplierHint {
  final String supplierKey;
  final HintField field;
  final String label;
  final int hits;
  const SupplierHint(this.supplierKey, this.field, this.label, this.hits);
}

/// Learning where a supplier prints a field, from the user's own
/// corrections. It remembers the printed words next to the value (never a
/// position on the page), so a crooked or differently cropped photo still
/// works.
class SupplierHints {
  const SupplierHints._();

  /// The same supplier written in different ways gives the same key.
  static String key(String supplier) => supplier
      .toLowerCase()
      .replaceAll(RegExp('[åä]'), 'a')
      .replaceAll('ö', 'o')
      .replaceAll(RegExp(r'\b(ab|hb|kb|aktiebolag|handelsbolag)\b'), '')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  static final _split = RegExp(r'\s{3,}');

  /// Where [value] stands in [rows]: (row index, start, end), or null.
  static (int, int, int)? _find(List<String> rows, HintField field, String value) {
    final v = value.trim();
    if (v.isEmpty) return null;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      switch (field) {
        case HintField.total || HintField.vat:
          final money = Money.parse(v);
          if (money == null) return null;
          for (final t in TextPatterns.amounts(row)) {
            if (t.value.abs() == money.abs() && t.hasDecimals) return (i, t.start, t.end);
          }
        case HintField.number || HintField.ocr:
          final digits = v.replaceAll(' ', '');
          if (digits.length < 3) return null;
          final pattern = digits.split('').map(RegExp.escape).join(r'\s?');
          final m = RegExp('(?<![0-9A-Za-z])$pattern(?![0-9])').firstMatch(row);
          if (m != null) return (i, m.start, m.end);
        case HintField.date || HintField.due:
          if (TextPatterns.dates(row).contains(v)) {
            final m = RegExp(r'\d').firstMatch(row);
            if (m != null) return (i, m.start, m.start + 1);
          }
      }
    }
    return null;
  }

  /// The words printed just before [value] on the paper: in its column on
  /// the same row, or the label row above it. Null when no label is found.
  static String? labelFor(List<String> rows, HintField field, String value) {
    final at = _find(rows, field, value);
    if (at == null) return null;
    final (i, start, _) = at;
    final row = rows[i];
    final before = row.substring(0, start).split(_split).where((c) => c.trim().isNotEmpty).toList();
    final same = before.isEmpty ? null : _clean(before.last);
    if (same != null) return same;
    // A row of labels above the values: the same column there.
    if (i > 0) {
      final col = _split.allMatches(row).where((g) => g.start < start).length;
      final above = rows[i - 1].split(_split);
      if (col < above.length) return _clean(above[col]);
    }
    return null;
  }

  static String? _clean(String text) {
    final t = text.toLowerCase().replaceAll(RegExp(r'[:.\s]+$'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (!RegExp(r'[a-zåäö]{3,}').hasMatch(t) || t.length > 40) return null;
    // A label is words, not another amount or date.
    if (TextPatterns.amounts(t).isNotEmpty || TextPatterns.dates(t).isNotEmpty) return null;
    return t;
  }

  /// Reads [field] after [label] in [rows]: on the same row, in the same
  /// column of the row below, or at the start of the row below.
  static String? read(List<String> rows, HintField field, String label) {
    for (var i = 0; i < rows.length; i++) {
      final lower = rows[i].toLowerCase();
      var at = lower.indexOf(label);
      if (at < 0) {
        // A label read with a letter wrong still counts.
        final words = label.split(' ').length;
        final tokens = lower.split(RegExp(r'\s+'));
        for (var k = 0; k + words <= tokens.length && at < 0; k++) {
          final candidate = tokens.sublist(k, k + words).join(' ').replaceAll(RegExp(r'[:.]+$'), '');
          if (candidate.length >= 4 && TextPatterns.similarity(candidate, label) >= 0.85) {
            at = lower.indexOf(tokens[k]);
          }
        }
      }
      if (at < 0) continue;
      final end = at + label.length;
      final after = rows[i].substring(end.clamp(0, rows[i].length));
      final segment = after.split(_split).where((c) => c.trim().isNotEmpty).toList();
      final here = _value(field, segment.isEmpty ? after : segment.first);
      if (here != null) return here;
      if (i + 1 < rows.length) {
        final col = _split.allMatches(rows[i]).where((g) => g.start < at).length;
        final below = rows[i + 1].split(_split);
        if (col < below.length) {
          final v = _value(field, below[col]);
          if (v != null) return v;
        }
        final first = _value(field, rows[i + 1]);
        if (first != null) return first;
      }
    }
    return null;
  }

  static String? _value(HintField field, String text) {
    switch (field) {
      case HintField.total || HintField.vat:
        final a = TextPatterns.amounts(text).where((t) => t.hasDecimals).firstOrNull;
        return a?.value.abs().toInput();
      case HintField.number:
        return RegExp(r'[A-Za-z]{0,4}-?\d[\d\-/]{0,19}(?![A-Za-zÅÄÖåäö\d])').firstMatch(text.trim())?[0];
      case HintField.ocr:
        return RegExp(r'(?<![\d,.])\d(?: ?\d){4,24}(?![\d]|\s?[,.]\d)').firstMatch(text)?[0]?.replaceAll(' ', '');
      case HintField.date || HintField.due:
        return TextPatterns.dates(text).firstOrNull;
    }
  }
}
