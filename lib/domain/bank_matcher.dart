import 'bank_statement.dart';
import 'dates.dart';
import 'models.dart';
import 'text_patterns.dart';

/// A bank payment that pays one of the unpaid invoices.
class BankMatch {
  final BankRow row;
  final Invoice invoice;

  /// The supplier's name, or the invoice or OCR number, is in the bank text,
  /// and no other invoice or payment could be the one. Only these are ticked
  /// at first; the user decides about the rest.
  final bool sure;
  const BankMatch(this.row, this.invoice, {required this.sure});
}

class BankMatchResult {
  final List<BankMatch> matches;

  /// Payments out that pay no unpaid invoice: a prompt to look for a missing
  /// invoice or receipt.
  final List<BankRow> unmatchedOut;
  final int unmatchedIn;
  const BankMatchResult(this.matches, this.unmatchedOut, this.unmatchedIn);
}

class BankMatcher {
  const BankMatcher._();

  /// Words that tell nothing about who a supplier is.
  static const _stopWords = {
    'aktiebolag',
    'handelsbolag',
    'kommanditbolag',
    'sverige',
    'svenska',
    'nordic',
    'group',
    'scandinavia',
  };

  /// Pairs payments with unpaid invoices. The amount must be exactly the
  /// invoice's total to the öre (a credit note is a payment in), and the
  /// payment may not be more than a week before the invoice date. Each
  /// payment and each invoice is used once.
  static BankMatchResult match(List<BankRow> rows, List<Invoice> unpaid) {
    final pairs = <_Pair>[];
    for (var r = 0; r < rows.length; r++) {
      for (var i = 0; i < unpaid.length; i++) {
        final row = rows[r];
        final inv = unpaid[i];
        if (inv.total.isZero || row.amount != -inv.total) continue;
        final days = _days(inv.invoiceDate, row.date);
        if (days != null && days < -7) continue;
        pairs.add(_Pair(r, i, _named(row, inv), days?.abs() ?? 0));
      }
    }
    final perRow = <int, int>{};
    final perInvoice = <int, int>{};
    for (final p in pairs) {
      perRow[p.row] = (perRow[p.row] ?? 0) + 1;
      perInvoice[p.invoice] = (perInvoice[p.invoice] ?? 0) + 1;
    }
    // A name in the text first, then the payment closest to the invoice date.
    pairs.sort((a, b) {
      if (a.named != b.named) return a.named ? -1 : 1;
      final d = a.distance.compareTo(b.distance);
      if (d != 0) return d;
      final r = a.row.compareTo(b.row);
      return r != 0 ? r : a.invoice.compareTo(b.invoice);
    });
    final usedRows = <int>{};
    final usedInvoices = <int>{};
    final matches = <BankMatch>[];
    for (final p in pairs) {
      if (usedRows.contains(p.row) || usedInvoices.contains(p.invoice)) continue;
      usedRows.add(p.row);
      usedInvoices.add(p.invoice);
      matches.add(BankMatch(rows[p.row], unpaid[p.invoice],
          sure: p.named && perRow[p.row] == 1 && perInvoice[p.invoice] == 1));
    }
    matches.sort((a, b) => b.row.date.compareTo(a.row.date));
    final rest = [
      for (var r = 0; r < rows.length; r++)
        if (!usedRows.contains(r)) rows[r],
    ];
    return BankMatchResult(
        matches, [for (final r in rest) if (r.amount.isNegative) r], rest.where((r) => !r.amount.isNegative).length);
  }

  /// Whole days from [fromIso] to [toIso], or null when a date does not parse.
  static int? _days(String fromIso, String toIso) {
    final a = SwedishDates.parseIso(fromIso);
    final b = SwedishDates.parseIso(toIso);
    if (a == null || b == null) return null;
    return DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
  }

  static bool _named(BankRow row, Invoice inv) {
    final text = TextPatterns.normalize(row.text);
    final words = TextPatterns.normalize(inv.supplier)
        .split(RegExp(r'[^a-zåäöé0-9]+'))
        .where((w) => w.length >= 4 && !_stopWords.contains(w));
    if (words.any((w) => text.contains(w))) return true;
    for (final number in [inv.invoiceNumber, inv.ocrReference]) {
      final digits = number.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 4 && RegExp('(?<!\\d)$digits(?!\\d)').hasMatch(row.text)) return true;
    }
    return false;
  }
}

class _Pair {
  final int row;
  final int invoice;
  final bool named;
  final int distance;
  const _Pair(this.row, this.invoice, this.named, this.distance);
}
