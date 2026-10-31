import 'money.dart';
import 'patterns.dart';
import 'vat.dart';

class InvoiceVatLine {
  const InvoiceVatLine(this.ratePercent, this.vat, {this.net});
  final int ratePercent;
  final Money vat;

  /// Taxable amount for this rate, when the invoice prints it.
  final Money? net;
}

class AmountCandidate {
  const AmountCandidate(this.value, this.score, this.line);
  final Money value;
  final double score;
  final String line;
}

class InvoiceExtraction {
  const InvoiceExtraction({
    this.date,
    this.dateConfidence = Confidence.low,
    this.dueDate,
    this.invoiceNumber,
    this.ocrReference,
    this.supplier,
    this.total,
    this.totalConfidence = Confidence.low,
    this.net,
    this.vatLines = const [],
    this.vatTotal,
    this.vatConfidence = Confidence.low,
    this.candidates = const [],
  });

  final String? date, dueDate, invoiceNumber, ocrReference, supplier;
  final Confidence dateConfidence, totalConfidence, vatConfidence;
  final Money? total, net, vatTotal;
  final List<InvoiceVatLine> vatLines;
  final List<AmountCandidate> candidates;
}

class _Line {
  _Line(this.i, this.s) : a = amountsIn(s), l = s.toLowerCase();
  final int i;
  final String s, l;
  final List<Money> a;
}

class _Cand {
  _Cand(this.idx, this.v, this.score, this.line);
  final int idx;
  final Money v;
  double score;
  final String line;
}

double _labelScore(String l) {
  var sc = 0.0;
  if (l.contains('att betala')) {
    sc += 10;
  } else if (l.contains('totalt belopp')) {
    sc += 9;
  } else if (RegExp(r'\btotalt\b').hasMatch(l)) {
    sc += 7;
  } else if (RegExp(r'\btotal\b').hasMatch(l)) {
    sc += 6;
  } else if (RegExp(r'\bsumma\b').hasMatch(l)) {
    sc += 5;
  }
  if (RegExp(r'kontant|erhållet|mottaget|växel|tillbaka|lämnat|betalt belopp').hasMatch(l)) {
    sc -= 20;
  }
  if (RegExp(r'netto|exkl|ex\.? moms|delsumma|subtotal|rabatt|före moms|utan moms').hasMatch(l)) {
    sc -= 8;
  } else if (l.contains('moms') && !l.contains('inkl')) {
    sc -= 8;
  }
  return sc;
}

/// Ranks monetary candidates by label, context, arithmetic and position.
/// Never takes "the largest number": cash tendered and change are penalised,
/// and a candidate equal to (other − change) is treated as tendered cash.
InvoiceExtraction extractInvoice(String text) {
  final raw = cleanLines(text);
  final lines = [for (var i = 0; i < raw.length; i++) _Line(i, raw[i])];

  final cands = <_Cand>[];
  for (var k = 0; k < lines.length; k++) {
    final ln = lines[k];
    var a = ln.a;
    if (a.isEmpty &&
        k + 1 < lines.length &&
        RegExp(r'att betala|totalt|summa|total').hasMatch(ln.l) &&
        lines[k + 1].a.isNotEmpty) {
      a = [lines[k + 1].a.first];
    }
    if (a.isEmpty) continue;
    final sc = _labelScore(ln.l) + ln.i / raw.length * 2;
    cands.add(_Cand(ln.i, a.last, sc, ln.s));
  }

  var change = 0;
  for (final x in lines) {
    if (x.a.isNotEmpty && RegExp(r'växel|tillbaka').hasMatch(x.l)) change += x.a.last.ore;
  }
  for (final c in cands) {
    if (c.score >= 5 &&
        lines.any((x) =>
            RegExp(r'betalt|kort|swish').hasMatch(x.l) &&
            !x.l.contains('betalt belopp') &&
            x.a.contains(c.v))) {
      c.score += 3;
    }
    if (change != 0 &&
        cands.any((o) => !identical(o, c) && o.v.ore == c.v.ore - change && o.score >= 5)) {
      c.score -= 10;
    }
  }
  cands.sort((a, b) {
    final d = b.score.compareTo(a.score);
    return d != 0 ? d : a.idx.compareTo(b.idx);
  });

  Money? total;
  var tconf = Confidence.low;
  if (cands.isNotEmpty && cands.first.score >= 5) {
    final best = cands.first;
    _Cand? second;
    for (final c in cands) {
      if (c.v != best.v) {
        second = c;
        break;
      }
    }
    total = best.v;
    tconf = (best.score >= 10 && (second == null || best.score - second.score >= 3))
        ? Confidence.high
        : best.score >= 7
            ? Confidence.medium
            : Confidence.low;
  }

  Money? net;
  for (final x in lines) {
    if (x.a.isNotEmpty && RegExp(r'netto|exkl|före moms|utan moms|momspliktig').hasMatch(x.l)) {
      net = x.a.last;
      break;
    }
  }

  final vats = <InvoiceVatLine>[];
  Money? vt;
  final pctRe = RegExp(r'(\d{1,2})(?:[.,]0+)?\s*%');
  for (final ln in lines) {
    final rm = pctRe.firstMatch(ln.s.replaceAll(dateRe, ' '));
    if (rm != null && ln.a.isNotEmpty && RegExp(r'moms|mva|%').hasMatch(ln.l)) {
      final r = int.parse(rm.group(1)!);
      if (![0, 6, 12, 25].contains(r) || vats.any((x) => x.ratePercent == r)) continue;
      Money? v, vNet;
      if (ln.a.length == 1 && ln.l.contains('moms')) {
        v = ln.a.first;
      } else if (ln.a.length >= 2) {
        for (final n in ln.a) {
          for (final x in ln.a) {
            if (n != x && (x.ore - VatCalculator.divRound(n.ore * r, 100)).abs() <= 100) {
              v = x;
              vNet = n;
            }
          }
        }
        if (v == null && ln.l.contains('moms')) v = ln.a.last;
      }
      if (v != null) vats.add(InvoiceVatLine(r, v, net: vNet));
    } else if (rm == null &&
        ln.l.contains('moms') &&
        ln.a.length == 1 &&
        !RegExp(r'exkl|inkl|före|utan|momspliktig').hasMatch(ln.l)) {
      vt = ln.a.first;
    }
  }

  // Column table: "Moms% Moms Netto Brutto" followed by one row per rate.
  final tableHeader = RegExp(r'moms\s*%?\s+moms\s+netto\s+brutto');
  final tableNets = <Money>[];
  for (var k = 0; k < lines.length; k++) {
    if (!tableHeader.hasMatch(lines[k].l)) continue;
    for (var j = k + 1; j < lines.length; j++) {
      final a = lines[j].a;
      if (a.length < 4 || a[0].ore % 100 != 0) break;
      final rate = a[0].ore ~/ 100;
      if (![0, 6, 12, 25].contains(rate)) break;
      if (!vats.any((x) => x.ratePercent == rate)) {
        vats.add(InvoiceVatLine(rate, a[1], net: a[2]));
        tableNets.add(a[2]);
      }
    }
  }
  if (net == null && tableNets.isNotEmpty) net = Money.sum(tableNets);

  Money? vat;
  var vconf = Confidence.low;
  if (vats.isNotEmpty) {
    vat = Money.sum(vats.map((x) => x.vat));
    vconf = (vt == null || vt == vat) ? Confidence.medium : Confidence.low;
  } else if (vt != null) {
    vat = vt;
    vconf = Confidence.medium;
  }
  if (vat != null && total != null) {
    if (net != null && (net.ore + vat.ore - total.ore).abs() <= 100) {
      vconf = Confidence.high;
    } else if (vat.ore > VatCalculator.divRound(total.ore * 25, 125) + 100) {
      vconf = Confidence.low;
    }
  }

  String? date, due;
  var dconf = Confidence.low;
  // Column layouts: the header "Förfallodatum ..." is on one row, the dates on the next.
  final consumed = <int>{};
  for (var k = 0; k < lines.length - 1; k++) {
    if (lines[k].l.contains('förfall') && datesIn(lines[k].s).isEmpty) {
      final d = datesIn(lines[k + 1].s);
      if (d.isNotEmpty) {
        due ??= d.first;
        consumed.add(k + 1);
      }
    }
  }
  for (final ln in lines) {
    if (consumed.contains(ln.i)) continue;
    final d = datesIn(ln.s);
    if (d.isEmpty) continue;
    if (ln.l.contains('förfall')) {
      due ??= d.first;
      continue;
    }
    if (RegExp(r'fakturadatum|datum').hasMatch(ln.l)) {
      if (dconf != Confidence.high) {
        date = d.first;
        dconf = Confidence.high;
      }
      continue;
    }
    if (date == null) {
      date = d.first;
      dconf = Confidence.medium;
    }
  }

  final nr = RegExp(r'faktura\s*(?:nummer|nr)\.?\s*[:#]?\s*([A-Za-z0-9-]+)',
          caseSensitive: false)
      .firstMatch(text)
      ?.group(1);
  final ocr =
      RegExp(r'\bOCR\b[^\d\n]*(\d{6,})', caseSensitive: false).firstMatch(text)?.group(1);
  String? supplier;
  final notName = RegExp(r'faktura|kvitto|datum|org|bankgiro|ocr|kundnr|nr\b|sida|ordernr|referens',
      caseSensitive: false);
  for (final s in raw) {
    if (RegExp(r'\b(AB|HB|KB|Aktiebolag)\b').hasMatch(s) && !notName.hasMatch(s)) {
      supplier = s;
      break;
    }
  }
  if (supplier == null) {
    for (final s in raw) {
      final letters = RegExp(r'[A-Za-zÅÄÖåäö]').allMatches(s).length;
      if (letters >= 3 && letters / s.length > 0.6 && !notName.hasMatch(s)) {
        supplier = s;
        break;
      }
    }
  }

  return InvoiceExtraction(
    date: date,
    dateConfidence: dconf,
    dueDate: due,
    invoiceNumber: nr,
    ocrReference: ocr,
    supplier: supplier,
    total: total,
    totalConfidence: tconf,
    net: net,
    vatLines: vats,
    vatTotal: vat,
    vatConfidence: vconf,
    candidates: [for (final c in cands.where((c) => c.score >= 5).take(3)) AmountCandidate(c.v, c.score, c.line)],
  );
}
