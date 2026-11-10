/// Business dates are stored as ISO strings (`2026-10-28`) so they sort and
/// compare without time-zone effects.
class SwedishDates {
  const SwedishDates._();

  static const months = [
    'januari', 'februari', 'mars', 'april', 'maj', 'juni',
    'juli', 'augusti', 'september', 'oktober', 'november', 'december',
  ];
  static const shortMonths = [
    'jan', 'feb', 'mar', 'apr', 'maj', 'jun',
    'jul', 'aug', 'sep', 'okt', 'nov', 'dec',
  ];

  static String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

  /// Returns null unless [s] is a real calendar date in `YYYY-MM-DD` form.
  static DateTime? parseIso(String s) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s.trim());
    if (m == null) return null;
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    final date = DateTime(y, mo, d);
    if (date.year != y || date.month != mo || date.day != d) return null;
    return date;
  }

  static bool isValidIso(String s) => parseIso(s) != null;

  /// `28 okt`
  static String shortDay(String isoDate) {
    final d = parseIso(isoDate);
    if (d == null) return isoDate;
    return '${d.day} ${shortMonths[d.month - 1]}';
  }

  /// `28 okt 2026`
  static String mediumDay(String isoDate) {
    final d = parseIso(isoDate);
    if (d == null) return isoDate;
    return '${d.day} ${shortMonths[d.month - 1]} ${d.year}';
  }

  /// `Oktober 2026`
  static String monthTitle(int year, int month) => '${capitalize(months[month - 1])} $year';

  static String capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// `2026-10`
  static String monthKey(int year, int month) => '${year.toString().padLeft(4, '0')}-${_two(month)}';

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// The Monday of [d]'s week (Swedish weeks start on Monday).
  static DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

  /// ISO 8601 week number, as on Swedish calendars: week 1 holds the year's first Thursday.
  static int isoWeek(DateTime d) {
    // UTC, so a summer-time hour never shortens a day in the subtraction.
    final thursday = DateTime.utc(d.year, d.month, d.day + 4 - d.weekday);
    final dayOfYear = thursday.difference(DateTime.utc(thursday.year, 1, 1)).inDays;
    return dayOfYear ~/ 7 + 1;
  }
}
