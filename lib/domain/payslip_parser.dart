import 'dates.dart';
import 'document_parser.dart';
import 'money.dart';
import 'ocr_models.dart';
import 'text_patterns.dart';

/// What the reader found on a lönebesked. Everything is only a suggestion for
/// the review page; nothing printed is changed silently.
class PayslipDraft {
  final Extracted<String> payoutDate;
  final Extracted<String> periodFrom;
  final Extracted<String> periodTo;

  /// A likelier end of the period when the printed one is not after the start
  /// (the camera text can misread a year). Offered to the user, never applied.
  final String? periodToSuggestion;
  final Extracted<String> employeeName;
  final Extracted<String> personnummer;
  final Extracted<Money> gross;
  final Extracted<Money> employerFee;
  final Extracted<Money> tax;
  final Extracted<Money> net;

  /// The arbetsgivaravgift rate printed on the paper, in percent.
  final double? feeRate;
  final List<String> notes;

  const PayslipDraft({
    required this.payoutDate,
    required this.periodFrom,
    required this.periodTo,
    required this.employeeName,
    required this.personnummer,
    required this.gross,
    required this.employerFee,
    required this.tax,
    required this.net,
    required this.notes,
    this.periodToSuggestion,
    this.feeRate,
  });
}

class _Val {
  final Money? money;
  final double? percent;
  const _Val(this.money, this.percent);
}

class _Pair {
  final String label;
  final _Val value;
  const _Pair(this.label, this.value);
}

/// Reads a lönebesked (also called lönespecifikation).
///
/// Many payslips print a row of column headings and the values on the next
/// row, so the camera text has "Preliminär skatt   Bruttolön" and, below it,
/// "31,00%   7020,00". Labels and values are matched by position (from the
/// right when one value is missing), and a label with its amount on the same
/// row is read too. The sums on the paper then check the reading: bruttolön
/// minus preliminär skatt must give the nettolön.
class PayslipParser implements DocumentParser<PayslipDraft> {
  const PayslipParser();

  static final _gap = RegExp(r'\s{2,}');
  static final _pnr = RegExp(r'(?<!\d)(\d{6}|\d{8})\s?[-+_]\s?(\d{4})(?!\d)');

  @override
  PayslipDraft parse(OcrResult ocr) {
    final rows = [for (final r in ocr.rows()) r.text];
    final norm = [for (final t in rows) TextPatterns.normalize(t)];
    final notes = <String>[];
    final pairs = _pairs(rows);

    List<_Pair> labelled(bool Function(String) test) => [for (final p in pairs) if (test(p.label)) p];
    List<Money> amounts(List<_Pair> ps) => [for (final p in ps) if (p.value.money != null) p.value.money!];

    final grossPairs = labelled((l) =>
        !l.startsWith('ack') &&
        (l.contains('bruttolön') || l.contains('bruttolon') || l.contains('grundande') || l == 'brutto'));
    final feePairs = labelled((l) => !l.startsWith('ack') && (l.contains('arbetsgivaravgift') || l.contains('sociala avg')));
    final taxPairs = labelled((l) =>
        !l.startsWith('ack') &&
        (l.contains('preliminär skatt') ||
            l.contains('preliminar skatt') ||
            l.contains('preliminärskatt') ||
            l.contains('skatteavdrag') ||
            l.contains('avdragen skatt')));
    final netPairs = labelled((l) => l.contains('nettolön') || l.contains('nettolon') || l.contains('nettoion'));

    var grossC = amounts(grossPairs);
    if (grossC.isEmpty) grossC = _tableGross(rows);
    final taxC = amounts(taxPairs);
    final netC = amounts(netPairs);
    final everyAmount = {for (final p in pairs) if (p.value.money != null) p.value.money!};

    // The sums on the paper decide: bruttolön − skatt = nettolön.
    Money? gross;
    Money? tax;
    var sumsHold = false;
    for (final g in grossC.toSet()) {
      for (final t in taxC.toSet()) {
        if (!t.isZero && (netC.contains(g - t) || everyAmount.contains(g - t))) {
          gross = g;
          tax = t;
          sumsHold = true;
        }
      }
    }
    if (gross == null && grossC.isNotEmpty) {
      // The amount printed most often, e.g. both "Skattegrundande lön" and "Bruttolön".
      final counts = <Money, int>{};
      for (final g in grossC) {
        counts[g] = (counts[g] ?? 0) + 1;
      }
      gross = (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    }
    tax ??= taxC.where((t) => !t.isZero).firstOrNull ?? taxC.firstOrNull;

    final rate = [for (final p in feePairs) if (p.value.percent != null) p.value.percent!].firstOrNull;
    Money? fee = amounts(feePairs).firstOrNull;
    var feeCalculated = false;
    if (fee == null && rate != null && gross != null) {
      fee = Money((gross.ore * rate / 100 / 100).round() * 100);
      feeCalculated = true;
    }

    Extracted<Money> money(Money? v, {required Confidence sure, String? note}) =>
        v == null ? const Extracted.none() : Extracted(v, sure, note: note);

    final grossRepeats = gross != null && grossC.where((g) => g == gross).length > 1;
    final extractedGross = money(gross, sure: sumsHold || grossRepeats ? Confidence.high : Confidence.medium);
    final extractedTax = money(tax, sure: sumsHold ? Confidence.high : Confidence.medium);
    Extracted<Money> extractedFee = const Extracted.none();
    if (fee != null) {
      final expected = gross != null && rate != null ? gross.ore * rate / 100 / 100 : null;
      final agrees = expected != null && (fee.ore - expected * 100).abs() <= 100;
      extractedFee = Extracted(
        fee,
        feeCalculated
            ? Confidence.medium
            : agrees
                ? Confidence.high
                : Confidence.medium,
        note: feeCalculated ? 'Räknad från procentsatsen ${_pct(rate!)} %. Kontrollera.' : null,
      );
      if (gross != null && fee.ore > gross.ore * 35 / 100) {
        notes.add('Arbetsgivaravgiften är över 35 % av bruttolönen. Kontrollera.');
      }
    }
    Extracted<Money> extractedNet = const Extracted.none();
    final net = netC.firstOrNull ?? (gross != null && tax != null ? gross - tax : null);
    if (net != null) {
      extractedNet = Extracted(net, netC.isNotEmpty && sumsHold ? Confidence.high : Confidence.medium);
    }
    if (!extractedGross.hasValue) notes.add('Bruttolönen hittades inte. Fyll i den.');
    if (!extractedFee.hasValue) notes.add('Arbetsgivaravgiften hittades inte. Fyll i den, eller 0 om den saknas.');
    if (!extractedTax.hasValue) notes.add('Preliminär skatt hittades inte. Fyll i den, eller 0 om den saknas.');
    if (gross != null && tax != null && netC.isNotEmpty && !sumsHold) {
      notes.add('Bruttolön minus skatt blir inte nettolönen på pappret. Jämför med bilden.');
    }

    final payout = _payoutDate(rows, norm);
    if (!payout.hasValue) notes.add('Utbetalningsdatum hittades inte. Datumet avgör vilken månad kostnaden räknas till.');
    final (from, to, suggestion) = _period(rows, norm);
    final (pnr, name) = _person(rows, norm);
    if (!name.hasValue) notes.add('Namnet hittades inte. Fyll i det.');

    return PayslipDraft(
      payoutDate: payout,
      periodFrom: from,
      periodTo: to,
      periodToSuggestion: suggestion,
      employeeName: name,
      personnummer: pnr,
      gross: extractedGross,
      employerFee: extractedFee,
      tax: extractedTax,
      net: extractedNet,
      feeRate: rate,
      notes: notes,
    );
  }

  static String _pct(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  // ---------- labels and values ----------

  static _Val? _value(String chunk) {
    // "Anställningsnummer: 3" is a label with a number, not a value.
    final unitless = chunk.replaceAll(RegExp(r'\b(kr|sek)\b', caseSensitive: false), '');
    if (_hasLetter(unitless)) return null;
    final c = chunk.replaceAll(RegExp(r'[^\d,.\-%\s]'), '').trim();
    if (c.isEmpty || !RegExp(r'\d').hasMatch(c)) return null;
    if (c.endsWith('%')) {
      final p = double.tryParse(c.substring(0, c.length - 1).trim().replaceAll(',', '.').replaceAll(' ', ''));
      return p == null ? null : _Val(null, p);
    }
    final m = Money.parse(c);
    return m == null ? null : _Val(m, null);
  }

  static List<String> _chunks(String row) =>
      row.trim().split(_gap).map((c) => c.trim()).where((c) => c.isNotEmpty).toList();

  static bool _hasLetter(String s) => RegExp(r'[A-Za-zÅÄÖåäöÉé]{2,}').hasMatch(s);

  /// All label–value pairs: label rows followed by value rows, and a label
  /// with its amount in the next chunk or on the next row.
  static List<_Pair> _pairs(List<String> rows) {
    final out = <_Pair>[];
    var labels = <String>[];
    var values = <_Val>[];
    void flush() {
      if (labels.isNotEmpty && values.isNotEmpty) {
        final fromRight = values.length <= labels.length;
        final offset = fromRight ? labels.length - values.length : 0;
        for (var i = 0; i < values.length && offset + i < labels.length; i++) {
          out.add(_Pair(labels[offset + i], values[i]));
        }
      }
      labels = [];
      values = [];
    }

    for (var r = 0; r < rows.length; r++) {
      final chunks = _chunks(rows[r]);
      final vals = [for (final c in chunks) _value(c)];
      final allValues = chunks.isNotEmpty && vals.every((v) => v != null);
      final noValues = vals.every((v) => v == null);
      if (allValues) {
        if (labels.isNotEmpty) values.addAll(vals.cast<_Val>());
      } else if (noValues && _hasLetter(rows[r])) {
        if (values.isNotEmpty) flush();
        if (chunks.length == 1 && labels.isNotEmpty && RegExp(r'^[a-zåäö]').hasMatch(chunks[0])) {
          // A heading that wrapped onto its own line: "Preliminär" + "skatt".
          labels[labels.length - 1] = '${labels.last} ${TextPatterns.normalize(chunks[0])}';
        } else {
          labels.addAll(chunks.map(TextPatterns.normalize));
        }
      } else {
        flush();
      }
      // A label with its amount right after it: "Bruttolön   7 020,00".
      for (var k = 0; k + 1 < chunks.length; k++) {
        final v = vals[k + 1];
        if (vals[k] == null && _hasLetter(chunks[k]) && v != null) {
          out.add(_Pair(TextPatterns.normalize(chunks[k]), v));
        }
      }
      // A lone label and its amount on the next row.
      if (chunks.length == 1 && vals[0] == null && _hasLetter(chunks[0]) && r + 1 < rows.length) {
        final next = _chunks(rows[r + 1]);
        final v = next.length == 1 ? _value(next[0]) : null;
        if (v != null) out.add(_Pair(TextPatterns.normalize(chunks[0]), v));
      }
    }
    flush();
    return out;
  }

  /// Without a "Bruttolön" label: the amounts of the pay lines in the table
  /// ("Lön   Oktober   7020   7020,00"), added up.
  static List<Money> _tableGross(List<String> rows) {
    final lines = <Money>[];
    for (final row in rows) {
      final chunks = _chunks(row);
      if (chunks.length < 3) continue;
      final first = TextPatterns.normalize(chunks.first);
      if (!(first.startsWith('lön') || first.startsWith('lon'))) continue;
      final last = _value(chunks.last);
      if (last?.money != null && !last!.money!.isZero) lines.add(last.money!);
    }
    return lines.isEmpty ? const [] : [Money.sum(lines)];
  }

  // ---------- dates ----------

  static Extracted<String> _payoutDate(List<String> rows, List<String> norm) {
    for (var i = 0; i < rows.length; i++) {
      if (!RegExp(r'utbetalnings(?:datum|dag)|utbet\.? ?datum|lönedatum|lonedatum').hasMatch(norm[i])) continue;
      var d = TextPatterns.dates(rows[i]);
      if (d.isEmpty && i + 1 < rows.length) d = TextPatterns.dates(rows[i + 1]);
      if (d.isNotEmpty) return Extracted(d.first, Confidence.high, source: rows[i]);
    }
    return const Extracted.none();
  }

  /// (from, to, a likelier `to`). The end is marked unsure when it is not
  /// after the start.
  static (Extracted<String>, Extracted<String>, String?) _period(List<String> rows, List<String> norm) {
    for (var i = 0; i < rows.length; i++) {
      if (!RegExp(r'löneperiod|loneperiod|^period').hasMatch(norm[i])) continue;
      final found = [
        ...TextPatterns.dates(rows[i]),
        if (i + 1 < rows.length) ...TextPatterns.dates(rows[i + 1]),
      ];
      if (found.isEmpty) continue;
      final from = found.first;
      final to = found.length > 1 ? found[1] : null;
      if (to == null) return (Extracted(from, Confidence.medium, source: rows[i]), const Extracted.none(), null);
      if (to.compareTo(from) >= 0) {
        return (Extracted(from, Confidence.high, source: rows[i]), Extracted(to, Confidence.high, source: rows[i]), null);
      }
      return (
        Extracted(from, Confidence.high, source: rows[i]),
        Extracted(to, Confidence.low, source: rows[i], note: 'Slutdatumet kommer före startdatumet. Kontrollera året.'),
        _likelierEnd(from, to),
      );
    }
    return (const Extracted.none(), const Extracted.none(), null);
  }

  /// The printed end with the start's year, or else the last day of the
  /// start's month.
  static String? _likelierEnd(String from, String to) {
    final f = SwedishDates.parseIso(from);
    final t = SwedishDates.parseIso(to);
    if (f == null || t == null) return null;
    final sameYear = SwedishDates.iso(DateTime(f.year, t.month, t.day));
    if (sameYear.compareTo(from) >= 0 && DateTime(f.year, t.month, t.day).month == t.month) return sameYear;
    return SwedishDates.iso(DateTime(f.year, f.month + 1, 0));
  }

  // ---------- the employee ----------

  static const _notNames = {
    'person', 'nr', 'nr.', 'pers', 'personnummer', 'till', 'sverige', 'lön', 'lönebesked', 'löneperiod', 'loneperiod',
    'anställningsnummer', 'bankkontonummer', 'utbetalningsdatum', 'adress', 'telefon', 'organisationsnummer',
    'löneart', 'benämning', 'belopp', 'antal', 'enhet', 'datum', 'info',
  };

  static bool _luhnOk(String ten) {
    var sum = 0;
    for (var i = 0; i < ten.length; i++) {
      var d = int.parse(ten[i]);
      if (i.isEven) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
    }
    return sum % 10 == 0;
  }

  static bool _looksLikeName(String chunk) {
    if (chunk.contains(RegExp(r'[\d:&@/]'))) return false;
    final words = chunk.trim().split(RegExp(r'\s+'));
    if (words.length < 2 || words.length > 4) return false;
    return words.every((w) =>
        RegExp(r"^[A-ZÅÄÖÉ][A-Za-zÅÄÖåäöéèü'\-]+$").hasMatch(w) && !_notNames.contains(TextPatterns.normalize(w)));
  }

  /// The employee's personnummer (the one near "Person nr", never the
  /// company's organisationsnummer) and the name printed beside it.
  static (Extracted<String>, Extracted<String>) _person(List<String> rows, List<String> norm) {
    final personRows = [for (var i = 0; i < rows.length; i++) if (RegExp(r'person ?nr|personnummer|pers\.? ?nr').hasMatch(norm[i])) i];
    final orgRows = [for (var i = 0; i < rows.length; i++) if (RegExp(r'organisationsnummer|org\.? ?nr').hasMatch(norm[i])) i];
    int near(List<int> of, int i) => of.isEmpty ? 99 : of.map((j) => (j - i).abs()).reduce((a, b) => a < b ? a : b);

    int? pnrRow;
    String? pnr;
    var best = -1;
    for (var i = 0; i < rows.length; i++) {
      for (final m in _pnr.allMatches(rows[i])) {
        final digits = '${m.group(1)}${m.group(2)}';
        final ten = digits.length == 12 ? digits.substring(2) : digits;
        // Closer to "Person nr" than to "Organisationsnummer"; a valid check digit helps.
        final score = (near(personRows, i) <= 2 ? 4 : 0) +
            (near(orgRows, i) <= 2 && near(personRows, i) > 1 ? -5 : 0) +
            (_luhnOk(ten) ? 1 : 0);
        if (score > best) {
          best = score;
          pnrRow = i;
          pnr = '${ten.substring(0, 6)}-${ten.substring(6)}';
        }
      }
    }
    final pnrSure = pnr == null
        ? const Extracted<String>.none()
        : Extracted(pnr, best >= 5 ? Confidence.high : Confidence.medium, source: rows[pnrRow!]);

    final around = pnrRow ?? (personRows.isEmpty ? null : personRows.first);
    Extracted<String> name = const Extracted.none();
    if (around != null) {
      // The rows after the personnummer first, then the ones before.
      final order = [for (var d = 0; d <= 3; d++) ...[around + d, if (d > 0) around - d]];
      for (final r in order) {
        if (r < 0 || r >= rows.length) continue;
        for (final chunk in _chunks(rows[r])) {
          if (_looksLikeName(chunk)) {
            name = Extracted(chunk.trim(), Confidence.medium, source: rows[r], note: 'Kontrollera stavningen.');
            break;
          }
        }
        if (name.hasValue) break;
      }
    }
    return (pnrSure, name);
  }
}
