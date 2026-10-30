import 'dart:math' as math;

import 'money.dart';
import 'patterns.dart';

class SalesCategory {
  const SalesCategory({
    required this.id,
    required this.name,
    required this.vatRatePercent,
    this.aliases = const [],
  });
  final String id, name;
  final int vatRatePercent;
  final List<String> aliases;
}

class ZLine {
  const ZLine({
    required this.label,
    required this.amount,
    required this.categoryId,
    required this.similarity,
    required this.confidence,
  });
  final String label;
  final Money amount;

  /// Empty = unassigned (user must choose).
  final String categoryId;
  final double similarity;
  final Confidence confidence;
}

class ZExtraction {
  const ZExtraction({
    this.date,
    this.dateConfidence = Confidence.low,
    this.zNumber,
    this.total,
    this.totalConfidence = Confidence.low,
    this.lines = const [],
  });
  final String? date, zNumber;
  final Confidence dateConfidence, totalConfidence;
  final Money? total;
  final List<ZLine> lines;

  Money get detailedSum =>
      Money.sum(lines.where((l) => l.categoryId.isNotEmpty && l.categoryId != 'x').map((l) => l.amount));
}

class CategoryMatch {
  const CategoryMatch(this.category, this.score);
  final SalesCategory? category;
  final double score;
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-zåäö ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

int _lev(String a, String b) {
  final m = List.generate(a.length + 1, (i) => List<int>.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    m[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    m[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      m[i][j] = math.min(math.min(m[i - 1][j] + 1, m[i][j - 1] + 1),
          m[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
    }
  }
  return m[a.length][b.length];
}

const _synonyms = {
  'food': 'mat', 'livsmedel': 'mat', 'beer': 'öl', 'wine': 'vin',
  'tobacco': 'tobak', 'candy': 'konfektyr', 'spirits': 'sprit',
};

String? _synonym(String label) {
  if (_synonyms.containsKey(label)) return _synonyms[label];
  for (final w in label.split(' ')) {
    if (_synonyms.containsKey(w)) return _synonyms[w];
  }
  return null;
}

/// Controlled fuzzy matching: >= 0.9 is auto-assigned, 0.6-0.9 is only a
/// suggestion the user must confirm, lower is left unassigned.
CategoryMatch matchCategory(List<SalesCategory> cats, String label) {
  final l = _norm(label);
  SalesCategory? best;
  var bs = 0.0;
  for (final c in cats) {
    for (final n in [c.name, ...c.aliases].map(_norm).where((s) => s.isNotEmpty)) {
      double s;
      if (l == n) {
        s = 1;
      } else if (l.split(' ').contains(n)) {
        s = .9;
      } else {
        s = 1 - _lev(l, n) / math.max(l.length, n.length);
        if (s > .85) s = .85;
      }
      if (s > bs) {
        bs = s;
        best = c;
      }
    }
    final syn = _synonym(l);
    if (syn != null && _norm(c.name) == syn && .7 > bs) {
      bs = .7;
      best = c;
    }
  }
  return CategoryMatch(best, bs);
}

final _totalRe = RegExp(
    r'total(?:t)? försäljning|dagsförsäljning|dagens försäljning|summa försäljning',
    caseSensitive: false);
final _skipRe = RegExp(
    r'kontant|kort|swish|växel|moms|total|summa|antal|kvitto|netto|brutto|z-?(nr|nummer)|datum|kassa|retur|rabatt|faktura',
    caseSensitive: false);

ZExtraction extractZReport(String text, List<SalesCategory> cats) {
  final lines = cleanLines(text);

  String? date;
  var dconf = Confidence.low;
  final all = <String>[];
  for (final s in lines) {
    final d = datesIn(s);
    if (d.isEmpty) continue;
    all.addAll(d);
    if (date == null && RegExp(r'datum|rapport|affärsdag', caseSensitive: false).hasMatch(s)) {
      date = d.first;
      dconf = Confidence.high;
    }
  }
  if (date == null && all.isNotEmpty) {
    date = all.first;
    dconf = all.toSet().length == 1 ? Confidence.medium : Confidence.low;
  }

  final znr = RegExp(r'z-?(?:nummer|nr)\.?\s*[:#]?\s*(\d+)', caseSensitive: false)
      .firstMatch(text)
      ?.group(1);

  Money? total;
  var tconf = Confidence.low;
  for (final s in lines) {
    final a = amountsIn(s);
    if (a.isNotEmpty &&
        RegExp(r'total(?:t)? försäljning|dagsförsäljning|dagens försäljning|summa försäljning|^total\b|^summa\b',
                caseSensitive: false)
            .hasMatch(s)) {
      total = a.last;
      tconf = Confidence.high;
      break;
    }
  }

  final out = <ZLine>[];
  for (final s in lines) {
    final a = amountsIn(s);
    if (a.isEmpty) continue;
    if (_skipRe.hasMatch(s) && !RegExp(r'försäljning', caseSensitive: false).hasMatch(s.replaceAll(_totalRe, ''))) {
      continue;
    }
    if (_totalRe.hasMatch(s)) continue;
    final label = s
        .replaceAll(amountRe, '')
        .replaceAll(RegExp(r'[\d%:]'), '')
        .replaceAll(RegExp(r'[.,]'), '')
        .trim();
    if (label.isEmpty) continue;
    final m = matchCategory(cats, label);
    out.add(ZLine(
      label: label,
      amount: a.last,
      categoryId: m.score >= .6 && m.category != null ? m.category!.id : '',
      similarity: m.score,
      confidence: m.score >= .9
          ? Confidence.high
          : m.score >= .6
              ? Confidence.medium
              : Confidence.low,
    ));
  }

  return ZExtraction(
    date: date,
    dateConfidence: dconf,
    zNumber: znr,
    total: total,
    totalConfidence: tconf,
    lines: out,
  );
}
