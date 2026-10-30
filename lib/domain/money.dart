/// Money as integer öre. Never use double for accounting amounts.
class Money implements Comparable<Money> {
  const Money(this.ore);
  factory Money.kronor(int kr) => Money(kr * 100);

  final int ore;
  static const zero = Money(0);

  Money operator +(Money o) => Money(ore + o.ore);
  Money operator -(Money o) => Money(ore - o.ore);
  Money operator -() => Money(-ore);
  bool get isZero => ore == 0;

  @override
  int compareTo(Money other) => ore.compareTo(other.ore);
  @override
  bool operator ==(Object other) => other is Money && other.ore == ore;
  @override
  int get hashCode => ore.hashCode;
  @override
  String toString() => format();

  static Money sum(Iterable<Money> items) =>
      items.fold<Money>(zero, (a, b) => a + b);

  /// "1 250,50 kr" with non-breaking spaces.
  String format({bool unit = true}) {
    final a = ore.abs();
    final kr = (a ~/ 100).toString();
    final buf = StringBuffer();
    for (var i = 0; i < kr.length; i++) {
      if (i > 0 && (kr.length - i) % 3 == 0) buf.write('\u00A0');
      buf.write(kr[i]);
    }
    final r = (a % 100).toString().padLeft(2, '0');
    final sign = ore < 0 ? '\u2212' : '';
    return '$sign$buf,$r${unit ? '\u00A0kr' : ''}';
  }

  /// Parses Swedish/OCR text. Returns null if invalid OR ambiguous
  /// (e.g. "1.250" or "1,250" alone) so the caller asks the user.
  static Money? parse(String raw) {
    var s = raw
        .trim()
        .replaceAll('\u2212', '-')
        .replaceAll(RegExp('[\u00A0\u202F\u2009]'), ' ');
    s = s
        .replaceFirst(RegExp(r'\s*(kr|sek|kronor|:-)\s*$', caseSensitive: false), '')
        .trim();
    var neg = false;
    if (s.startsWith('-')) {
      neg = true;
      s = s.substring(1).trim();
    } else if (s.startsWith('+')) {
      s = s.substring(1).trim();
    }
    if (s.endsWith('-')) {
      neg = true;
      s = s.substring(0, s.length - 1).trim();
    }
    if (s.isEmpty) return null;
    if (s.contains(' ')) {
      if (!RegExp(r'^\d{1,3}( \d{3})+([.,]\d{1,2})?$').hasMatch(s)) return null;
      s = s.replaceAll(' ', '');
    }
    if (!RegExp(r'^[\d.,]+$').hasMatch(s) || s.length > 15) return null;

    final lc = s.lastIndexOf(',');
    final ld = s.lastIndexOf('.');
    var di = -1;
    String? gs;
    if (lc >= 0 && ld >= 0) {
      di = lc > ld ? lc : ld;
      gs = lc > ld ? '.' : ',';
    } else if (lc >= 0 || ld >= 0) {
      final sep = lc >= 0 ? ',' : '.';
      final idx = s.lastIndexOf(sep);
      final after = s.length - idx - 1;
      if (s.split(sep).length > 2) {
        if (!_grouped(sep).hasMatch(s)) return null;
        gs = sep;
      } else if (after >= 1 && after <= 2) {
        di = idx;
      } else {
        return null;
      }
    }
    var ip = di >= 0 ? s.substring(0, di) : s;
    final fp = di >= 0 ? s.substring(di + 1) : '';
    if (fp.length > 2) return null;
    if (gs != null) {
      if (!_grouped(gs).hasMatch(ip)) return null;
      ip = ip.split(gs).join();
    }
    if (!RegExp(r'^\d+$').hasMatch(ip)) return null;
    final o = int.parse(ip) * 100 + int.parse(('${fp}00').substring(0, 2));
    return Money(neg ? -o : o);
  }

  static RegExp _grouped(String sep) =>
      RegExp('^\\d{1,3}(${RegExp.escape(sep)}\\d{3})+\$');
}
