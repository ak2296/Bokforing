import 'dart:convert';

import 'dates.dart';
import 'money.dart';

/// One transaction of a bank file. Kept only in memory while the import page
/// is open; nothing from a bank file is saved by the app.
class BankRow {
  /// The booking day, `2026-10-30`.
  final String date;

  /// Description and reference together, as the bank prints them.
  final String text;

  /// Negative when money left the account.
  final Money amount;
  final Money? balance;
  const BankRow({required this.date, required this.text, required this.amount, this.balance});
}

class BankStatement {
  final List<BankRow> rows;

  /// Things the user should know before trusting the import, in Swedish.
  final List<String> warnings;
  const BankStatement(this.rows, this.warnings);

  /// Reads a CSV export from an internet bank. Columns are found by their
  /// names, so banks that order them differently also work: a date column
  /// (Bokföringsdag, Transaktionsdag, Datum), Belopp, and optionally
  /// Beskrivning/Text, Referens and Saldo. A title line starting with `*`
  /// before the header is skipped. Throws [FormatException] with a Swedish
  /// message when the file is not such a CSV.
  static BankStatement parse(List<int> bytes) {
    var text = _decode(bytes);
    if (text.startsWith('﻿')) text = text.substring(1);
    final lines =
        text.split(RegExp(r'\r\n|\r|\n')).where((l) => l.trim().isNotEmpty && !l.startsWith('*')).toList();
    final headerAt = lines.indexWhere((l) => l.toLowerCase().contains('belopp'));
    if (headerAt < 0) throw const FormatException('Filen har ingen rubrikrad med kolumnen Belopp.');
    final delimiter = _delimiter(lines[headerAt]);
    final header = [for (final h in _split(lines[headerAt], delimiter)) h.trim().toLowerCase()];
    int? col(List<String> names) {
      for (final n in names) {
        final i = header.indexOf(n);
        if (i >= 0) return i;
      }
      return null;
    }

    final dateCol = col(const [
      'bokföringsdag',
      'bokföringsdatum',
      'transaktionsdag',
      'transaktionsdatum',
      'reskontradatum',
      'datum',
      'valutadag',
    ]);
    final amountCol = col(const ['belopp']);
    if (dateCol == null || amountCol == null) {
      throw const FormatException('Hittar inte kolumnerna för datum och belopp.');
    }
    final textCols = [
      for (final c in [col(const ['beskrivning', 'text', 'transaktion', 'specifikation']), col(const ['referens', 'meddelande'])])
        if (c != null) c,
    ];
    final balanceCol = col(const ['bokfört saldo', 'saldo']);

    final rows = <BankRow>[];
    var skipped = 0;
    for (final line in lines.skip(headerAt + 1)) {
      final f = _split(line, delimiter);
      final date = f.length > dateCol ? _isoDate(f[dateCol]) : null;
      final amount = f.length > amountCol ? Money.parse(f[amountCol]) : null;
      if (date == null || amount == null) {
        skipped++;
        continue;
      }
      final parts = <String>[];
      for (final c in textCols) {
        final s = c < f.length ? f[c].trim() : '';
        if (s.isNotEmpty && !parts.contains(s)) parts.add(s);
      }
      rows.add(BankRow(
        date: date,
        text: parts.join(' · '),
        amount: amount,
        balance: balanceCol != null && balanceCol < f.length ? Money.parse(f[balanceCol]) : null,
      ));
    }
    if (rows.isEmpty) throw const FormatException('Inga betalningar hittades i filen.');

    final warnings = <String>[];
    if (skipped > 0) {
      warnings.add('$skipped ${skipped == 1 ? 'rad' : 'rader'} gick inte att läsa och hoppades över.');
    }
    if (_balanceBreaks(rows) > 0) {
      warnings.add('Saldot stämmer inte mellan raderna. Filen kan sakna betalningar, så kontrollera att den '
          'omfattar hela perioden.');
    }
    return BankStatement(rows, warnings);
  }

  /// UTF-8 when the bytes are valid UTF-8, otherwise Windows-1252, which
  /// Swedish banks use. å, ä and ö are the same bytes in Latin-1.
  static String _decode(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  static String _delimiter(String header) {
    var best = ',';
    var count = 0;
    for (final d in const [',', ';', '\t']) {
      final n = d.allMatches(header).length;
      if (n > count) {
        best = d;
        count = n;
      }
    }
    if (count == 0) throw const FormatException('Kolumnerna i filen går inte att skilja åt.');
    return best;
  }

  /// Splits one line at [delimiter], keeping delimiters inside "quotes".
  static List<String> _split(String line, String delimiter) {
    final out = <String>[];
    final buf = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          buf.write(c);
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == delimiter) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    out.add(buf.toString());
    return out;
  }

  static String? _isoDate(String raw) {
    final s = raw.trim();
    final iso = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)
        ? s
        : RegExp(r'^\d{4}/\d{2}/\d{2}$').hasMatch(s)
            ? s.replaceAll('/', '-')
            : RegExp(r'^\d{8}$').hasMatch(s)
                ? '${s.substring(0, 4)}-${s.substring(4, 6)}-${s.substring(6)}'
                : null;
    return iso != null && SwedishDates.isValidIso(iso) ? iso : null;
  }

  /// Rows where the saldo does not follow from the neighbouring row. Banks
  /// list the newest row first or last; the order is taken from the dates.
  static int _balanceBreaks(List<BankRow> rows) {
    if (rows.length < 2 || rows.any((r) => r.balance == null)) return 0;
    final newestFirst = rows.first.date.compareTo(rows.last.date) >= 0;
    var breaks = 0;
    for (var i = 0; i < rows.length - 1; i++) {
      final newer = newestFirst ? rows[i] : rows[i + 1];
      final older = newestFirst ? rows[i + 1] : rows[i];
      if (newer.balance != older.balance! + newer.amount) breaks++;
    }
    return breaks;
  }
}
