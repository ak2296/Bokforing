/// An amount in SEK stored as integer öre. Never use floating point for money.
class Money implements Comparable<Money> {
  final int ore;
  const Money(this.ore);

  static const zero = Money(0);

  factory Money.kr(int kr, [int ore = 0]) => Money(kr * 100 + (kr < 0 ? -ore : ore));

  Money operator +(Money other) => Money(ore + other.ore);
  Money operator -(Money other) => Money(ore - other.ore);
  Money operator -() => Money(-ore);
  bool operator <(Money other) => ore < other.ore;
  bool operator >(Money other) => ore > other.ore;
  bool operator <=(Money other) => ore <= other.ore;
  bool operator >=(Money other) => ore >= other.ore;

  bool get isZero => ore == 0;
  bool get isNegative => ore < 0;
  Money abs() => Money(ore.abs());

  static Money sum(Iterable<Money> values) =>
      values.fold(Money.zero, (a, b) => a + b);

  @override
  int compareTo(Money other) => ore.compareTo(other.ore);

  @override
  bool operator ==(Object other) => other is Money && other.ore == ore;

  @override
  int get hashCode => ore.hashCode;

  @override
  String toString() => 'Money($ore öre)';

  /// Swedish display format: `1 250,50 kr`. With [compact], `,00` is dropped.
  String format({bool unit = true, bool compact = false}) {
    final negative = ore < 0;
    final abs = ore.abs();
    final kr = abs ~/ 100;
    final rest = abs % 100;
    final digits = kr.toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    var s = buf.toString();
    if (!(compact && rest == 0)) s += ',${rest.toString().padLeft(2, '0')}';
    if (negative) s = '-$s';
    return unit ? '$s kr' : s;
  }

  /// Plain text for an edit field: `1250,50`.
  String toInput() {
    final abs = ore.abs();
    final s = '${abs ~/ 100},${(abs % 100).toString().padLeft(2, '0')}';
    return ore < 0 ? '-$s' : s;
  }

  /// Parses Swedish and OCR amount formats. Returns null when the text is not
  /// an amount or when the decimal separator is ambiguous (e.g. `1.250`).
  ///
  /// Accepted: `1 250,50`, `1250,50`, `1.250,50`, `1,250.50`, `1250.50`,
  /// `125:-`, `125,-`, `12,5`, `1250`, `-34,00`, `34,00-`, with `kr`/`SEK`.
  static Money? parse(String input) {
    var s = input.trim();
    s = s.replaceAll(RegExp(r'(sek|kr)\.?', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'[\s   ]'), '');
    if (s.isEmpty) return null;

    var negative = false;
    if (s.startsWith('-') || s.startsWith('−')) {
      negative = true;
      s = s.substring(1);
    } else if (s.startsWith('+')) {
      s = s.substring(1);
    }
    if (s.endsWith('-') && !s.endsWith(':-') && !s.endsWith(',-')) {
      negative = !negative;
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith(':-') || s.endsWith(',-') || s.endsWith('.-')) {
      s = s.substring(0, s.length - 2);
      if (!RegExp(r'^\d+$').hasMatch(s)) return null;
    }
    if (!RegExp(r'^[\d.,]+$').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) {
      return null;
    }

    String intPart;
    String decPart = '';
    final lastComma = s.lastIndexOf(',');
    final lastDot = s.lastIndexOf('.');

    if (lastComma >= 0 && lastDot >= 0) {
      final decSep = lastComma > lastDot ? ',' : '.';
      final thouSep = decSep == ',' ? '.' : ',';
      final idx = s.lastIndexOf(decSep);
      intPart = s.substring(0, idx);
      decPart = s.substring(idx + 1);
      if (intPart.contains(decSep)) return null;
      if (!_validGrouping(intPart, thouSep)) return null;
      intPart = intPart.replaceAll(thouSep, '');
      if (decPart.isEmpty || decPart.length > 2) return null;
    } else if (lastComma >= 0 || lastDot >= 0) {
      final sep = lastComma >= 0 ? ',' : '.';
      final parts = s.split(sep);
      if (parts.length == 2) {
        final after = parts[1];
        if (after.length == 1 || after.length == 2) {
          intPart = parts[0];
          decPart = after;
        } else if (after.length == 3) {
          return null; // "1,250" or "1.250": ambiguous
        } else {
          return null;
        }
        if (intPart.isEmpty) intPart = '0';
      } else {
        // Several separators of one kind can only be thousands grouping.
        if (!_validGrouping(s, sep)) return null;
        intPart = s.replaceAll(sep, '');
      }
    } else {
      intPart = s;
    }

    if (!RegExp(r'^\d+$').hasMatch(intPart)) return null;
    if (decPart.isNotEmpty && !RegExp(r'^\d+$').hasMatch(decPart)) return null;
    if (intPart.length > 12) return null;
    final kr = int.parse(intPart);
    final ore = decPart.isEmpty ? 0 : int.parse(decPart.padRight(2, '0'));
    final value = kr * 100 + ore;
    return Money(negative ? -value : value);
  }

  static bool _validGrouping(String s, String sep) {
    if (!s.contains(sep)) return true;
    final groups = s.split(sep);
    if (groups.first.isEmpty || groups.first.length > 3) return false;
    return groups.skip(1).every((g) => g.length == 3);
  }
}
