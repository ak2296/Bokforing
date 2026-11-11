import 'package:local_auth/local_auth.dart';

/// The phone's fingerprint (or face) check. A thin layer so the lock can be
/// tested without a phone.
abstract class BiometricAuth {
  /// The phone has a sensor and at least one fingerprint or face is enrolled.
  Future<bool> available();

  /// Shows the phone's own prompt. False when it fails or is cancelled.
  Future<bool> authenticate(String reason);
}

class PhoneBiometric implements BiometricAuth {
  final _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    try {
      return (await _auth.canCheckBiometrics) && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      // Biometrics only: the app's own PIN is the fallback, not the phone's.
      return await _auth.authenticate(localizedReason: reason, biometricOnly: true);
    } catch (_) {
      return false;
    }
  }
}
