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

  static final _line = RegExp(
      r'(?:#\s*(\d[\d ]*\d)\s*#)?\s*(\d[\d ]{0,12}?) (\d{2})\s+(\d)\s*>\s*(\d{5,8})\s*#\s*(\d{2})\s*#');
  static final _ocrOnly = RegExp(r'#\s*(\d[\d ]{3,30}\d)\s*#');

  /// Finds the code line among [rows]; null when none is printed.
  static SlipCodeLine? find(List<String> rows) {
    for (final raw in rows.reversed) {
      final row = raw.replaceAll(RegExp(r'\s+'), ' ');
      final m = _line.firstMatch(row);
      if (m == null) continue;
      final ocr = m[1]?.replaceAll(' ', '');
      final kronor = m[2]!.replaceAll(' ', '');
      final digits = '$kronor${m[3]}';
      final amount = Money.parse('$kronor,${m[3]}');
      final account = m[5]!;
      return SlipCodeLine(
        source: raw,
        ocr: ocr != null && ocr.length >= 2 && luhnValid(ocr) ? ocr : null,
        amount: amount,
        amountChecked: luhnCheckDigit(digits) == int.parse(m[4]!),
        account: luhnValid(account) ? account : null,
        accountCode: m[6],
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
