import 'money.dart';

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'maj': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'okt': 10, 'nov': 11, 'dec': 12,
};

final dateRe = RegExp(
    r'\b(20\d{2})[-./](0?[1-9]|1[0-2])[-./](0?[1-9]|[12]\d|3[01])\b'
    r'|\b(0?[1-9]|[12]\d|3[01])[-./](0?[1-9]|1[0-2])[-./](20\d{2})\b'
    r'|\b(\d{1,2})\s+(jan|feb|mar|apr|maj|jun|jul|aug|sep|okt|nov|dec)[a-zåäö]*\.?\s+(20\d{2})\b',
    caseSensitive: false);

final amountRe = RegExp(
    r'(?:\d{1,3}(?:[ \u00A0.]\d{3})+|\d+)[.,]\d{2}(?!\d)'
    r'|\d{1,3}(?:[ \u00A0]\d{3})+(?=\s*(?:kr|sek)\b)'
    r'|\d+(?=\s*(?:kr|sek)\b)',
    caseSensitive: false);

/// ISO dates (YYYY-MM-DD) found in a line.
List<String> datesIn(String line) {
  final out = <String>[];
  for (final m in dateRe.allMatches(line)) {
    int y, mo, d;
    if (m.group(1) != null) {
      y = int.parse(m.group(1)!);
      mo = int.parse(m.group(2)!);
      d = int.parse(m.group(3)!);
    } else if (m.group(4) != null) {
      d = int.parse(m.group(4)!);
      mo = int.parse(m.group(5)!);
      y = int.parse(m.group(6)!);
    } else {
      d = int.parse(m.group(7)!);
      mo = _months[m.group(8)!.toLowerCase()]!;
      y = int.parse(m.group(9)!);
    }
    out.add('$y-${mo.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}');
  }
  return out;
}

/// Money amounts in a line (dates are ignored).
List<Money> amountsIn(String line) => amountRe
    .allMatches(line.replaceAll(dateRe, ' '))
    .map((m) => Money.parse(m.group(0)!))
    .whereType<Money>()
    .toList();

List<String> cleanLines(String text) => text
    .split(RegExp(r'\r?\n'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

enum Confidence { high, medium, low, manual }
