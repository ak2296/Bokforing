import 'money.dart';

/// The machine-read line at the bottom of a Swedish giro slip, printed in
/// the OCR-B font:
///
///     #  1234567897  #   159 00   4 >   50501055#41#
///
/// OCR reference, amount (kronor, öre and a check digit) and the payee's
/// bankgiro or plusgiro number. Each part carries a check digit (mod 10,
/// Luhn), so a part that passes the check is read right.
class SlipCodeLine {
  final String? ocr;
  final Money? amount;

  /// True when the amount's check digit fits.
  final bool amountChecked;

  /// Payee number, digits only, with a valid check digit.
  final String? account;

  /// The two digits between the closing "#…#": 41 for bankgiro.
  final String? accountCode;
  final String source;

  const SlipCodeLine({
    required this.source,
    this.ocr,
    this.amount,
    this.amountChecked = false,
    this.account,
    this.accountCode,
  });

  static final _ocrOnly = RegExp(r'#\s*(\d[\d ]{3,30}\d)\s*#');

  /// The payee number with its type code: "1262500#41#". OCR often reads a
  /// 5 as S, a 0 as O and a 1 as l or I.
  static final _account = RegExp(r'([0-9SOIl]{5,8})\s*#\s*(\d{2})\s*#');

  /// Kronor, öre and the check digit: "159 00 4", the ">" after it may be
  /// lost by OCR.
  static final _amount = RegExp(r'(?<![\d,.])(\d{1,9}) (\d{2})(?:\s+(\d))?(?![\d,.])');

  static String _digitsFromOcr(String s) =>
      s.replaceAll('S', '5').replaceAll('O', '0').replaceAll('I', '1').replaceAll('l', '1');

  /// Finds the code line among [rows]; null when none is printed. The line
  /// may be split over two rows and miss its "#" or ">" marks; every part
  /// is only used when its check digit fits (the amount also when it equals
  /// the total read elsewhere, see [amountChecked]).
  static SlipCodeLine? find(List<String> rows) {
    final marker = RegExp(r'#\s*\d{2}\s*#|\d\s*>');
    for (var k = rows.length - 1; k >= 0; k--) {
      if (!marker.hasMatch(rows[k])) continue;
      // The rows around the marker that carry digits make up the line.
      final window = [
        for (var i = k - 2; i <= k + 2; i++)
          if (i >= 0 && i < rows.length && RegExp(r'\d{2}').hasMatch(rows[i])) rows[i],
      ];
      final text = window.join(' ').replaceAll(RegExp(r'\s+'), ' ');
      String? account, code;
      var rest = text;
      final a = _account.firstMatch(text);
      if (a != null) {
        final digits = _digitsFromOcr(a[1]!);
        if (RegExp(r'^\d+$').hasMatch(digits) && luhnValid(digits)) {
          account = digits;
          code = a[2];
        }
        rest = text.replaceRange(a.start, a.end, ' ');
      }
      // The reference: the first long number whose check digit fits.
      String? ocr;
      var after = 0;
      for (final m in RegExp(r'(?<!\d)\d{6,25}(?!\d)').allMatches(rest)) {
        if (luhnValid(m[0]!)) {
          ocr = m[0];
          after = m.end;
          break;
        }
      }
      Money? amount;
      var checked = false;
      for (final m in _amount.allMatches(rest.substring(after))) {
        final kronor = m[1]!, ore = m[2]!;
        final value = Money.parse('$kronor,$ore');
        if (value == null || value.isZero) continue;
        amount = value;
        checked = m[3] != null && luhnCheckDigit('$kronor$ore') == int.parse(m[3]!);
        break;
      }
      if (ocr == null && amount == null && account == null) continue;
      return SlipCodeLine(
        source: window.join(' / '),
        ocr: ocr,
        amount: amount,
        amountChecked: checked,
        account: account,
        accountCode: code,
      );
    }
    // A slip with only the reference part read.
    for (final raw in rows.reversed) {
      final m = _ocrOnly.firstMatch(raw);
      final ocr = m?[1]?.replaceAll(' ', '');
      if (ocr != null && luhnValid(ocr)) return SlipCodeLine(source: raw, ocr: ocr);
    }
    return null;
  }

  /// The mod 10 (Luhn) check digit for [digits].
  static int luhnCheckDigit(String digits) {
    var sum = 0;
    var doubleIt = true;
    for (var i = digits.length - 1; i >= 0; i--) {
      var d = digits.codeUnitAt(i) - 48;
      if (doubleIt) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
      doubleIt = !doubleIt;
    }
    return (10 - sum % 10) % 10;
  }

  /// True when the last digit of [number] is its Luhn check digit.
  static bool luhnValid(String number) {
    if (number.length < 2 || !RegExp(r'^\d+$').hasMatch(number)) return false;
    return luhnCheckDigit(number.substring(0, number.length - 1)) == number.codeUnitAt(number.length - 1) - 48;
  }

  /// "50501055" → "5050-1055", "1234567" → "123-4567".
  static String bankgiroFormat(String d) => '${d.substring(0, d.length - 4)}-${d.substring(d.length - 4)}';

  /// "47926035" → "4792603-5".
  static String plusgiroFormat(String d) => '${d.substring(0, d.length - 1)}-${d.substring(d.length - 1)}';
}
