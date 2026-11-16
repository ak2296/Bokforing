import 'package:cryptography/cryptography.dart';

/// The company name and organisation number as one pair. A trial and an
/// activation belong to the pair: change either one and they stop applying.
class CompanyPair {
  /// Capitals, spaces, dots and signs do not matter: "Pizzeria Roma AB" and
  /// "pizzeria roma ab." are the same company.
  static String normalizeName(String name) => name.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

  /// Only the ten digits; the hyphen and spaces do not matter.
  static String normalizeOrg(String org) => org.replaceAll(RegExp(r'\D'), '');

  /// Ten digits that pass the Luhn check digit, as a Swedish organisation number does.
  static bool orgValid(String org) {
    final d = normalizeOrg(org);
    if (d.length != 10) return false;
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      var n = int.parse(d[i]);
      if (i.isEven) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
    }
    return sum % 10 == 0;
  }

  static bool same(String nameA, String orgA, String nameB, String orgB) =>
      normalizeName(nameA) == normalizeName(nameB) && normalizeOrg(orgA) == normalizeOrg(orgB);

  /// 64 hex characters that identify the pair on the server without showing it.
  static Future<String> hash(String name, String org) async {
    final h = await Sha256().hash('${normalizeName(name)}|${normalizeOrg(org)}'.codeUnits);
    return [for (final b in h.bytes) b.toRadixString(16).padLeft(2, '0')].join();
  }
}
