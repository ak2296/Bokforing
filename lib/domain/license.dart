import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'dates.dart';

enum LicenseStatus { missing, active, expired, revoked }

/// What an activation code says. A test code has no company and no end date.
class License {
  final String id;
  final String companyName;
  final String orgNumber;

  /// Last valid day as an ISO date; null means no end date.
  final String? until;
  const License({required this.id, this.companyName = '', this.orgNumber = '', this.until});

  /// The code fixes the company name and org number.
  bool get locksCompany => companyName.isNotEmpty;
}

class LicenseState {
  final License? license;
  final LicenseStatus status;
  const LicenseState(this.license, this.status);
}

/// Checks activation codes offline. The app holds only the public key, so it
/// can check codes but never create them.
class LicenseChecker {
  /// Pairs with the secret key the owner keeps outside this repository.
  static const appPublicKey = 'eCWPoIHq6owtHKiMMepmYHUA1h2-9DR2ApxjDAlIUHM';

  /// Codes ended by the owner. An id stays here for good, so an ended code
  /// never works again in this or any later version of the app.
  static const appRevoked = <String>{};

  final String publicKey;
  final Set<String> revoked;
  const LicenseChecker({this.publicKey = appPublicKey, this.revoked = appRevoked});

  static List<int> _decode(String s) => base64Url.decode(base64Url.normalize(s));

  /// The licence in [code], or null when the code is damaged or not signed
  /// with the owner's key.
  Future<License?> read(String code) async {
    final parts = code.replaceAll(RegExp(r'\s'), '').split('.');
    if (parts.length != 3 || parts[0] != 'BOK1') return null;
    try {
      final payload = _decode(parts[1]);
      final valid = await Ed25519().verify(
        payload,
        signature: Signature(_decode(parts[2]),
            publicKey: SimplePublicKey(_decode(publicKey), type: KeyPairType.ed25519)),
      );
      if (!valid) return null;
      final f = utf8.decode(payload).split('|');
      if (f.length != 4) return null;
      return License(id: f[0], companyName: f[1], orgNumber: f[2], until: f[3].isEmpty ? null : f[3]);
    } catch (_) {
      // Not base64, wrong length or other damage: simply not a valid code.
      return null;
    }
  }

  LicenseStatus statusOf(License? license, String todayIso) {
    if (license == null) return LicenseStatus.missing;
    if (revoked.contains(license.id)) return LicenseStatus.revoked;
    final until = license.until;
    if (until != null && SwedishDates.isValidIso(until) && todayIso.compareTo(until) > 0) {
      return LicenseStatus.expired;
    }
    return LicenseStatus.active;
  }
}
