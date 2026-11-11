import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'biometric.dart';

/// Where the lock keeps its state: the phone's secure storage in the app, a
/// map in tests. It is deliberately not the database: the database is part of
/// every backup, so a PIN kept there would be restored on a phone that has no
/// PIN, and would end up in the backup files.
abstract class LockStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureLockStore implements LockStore {
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

enum PinStatus { ok, wrong, locked }

class PinResult {
  final PinStatus status;

  /// For [PinStatus.locked]: how long until the next try.
  final Duration wait;

  /// For [PinStatus.wrong]: tries left before the waiting starts.
  final int triesLeft;
  const PinResult(this.status, {this.wait = Duration.zero, this.triesLeft = 0});
}

/// The PIN that opens the app. Only a salted hash is kept, and wrong tries
/// are counted in the same store, so closing the app does not reset them.
class PinLock extends ChangeNotifier {
  static const minLength = 4;
  static const maxLength = 6;
  static const freeTries = 5;

  /// Far less than the backup's 120 000: this runs at every unlock. The real
  /// protection is the secure storage and the waiting after wrong tries.
  static const _iterations = 15000;

  static const _kHash = 'pin_hash';
  static const _kSalt = 'pin_salt';
  static const _kLength = 'pin_length';
  static const _kFails = 'pin_fails';
  static const _kUntil = 'pin_locked_until';
  static const _kBiometric = 'pin_biometric';

  final LockStore _store;
  final DateTime Function() _now;
  bool _enabled = false;
  int _length = minLength;
  bool _useBiometric = false;

  /// The phone's fingerprint check; null in tests that do not need it.
  final BiometricAuth? biometric;

  PinLock(this._store, {DateTime Function()? now, this.biometric}) : _now = now ?? DateTime.now;

  bool get enabled => _enabled;

  /// Fingerprint opens the app too. Never without a PIN: the PIN is what
  /// opens it when the fingerprint does not work.
  bool get biometricEnabled => _enabled && _useBiometric && biometric != null;

  Future<bool> get biometricAvailable async => biometric != null && await biometric!.available();

  /// Turning it on asks for the fingerprint once, to show that it works.
  Future<bool> setBiometric(bool on) async {
    if (on) {
      if (!_enabled ||
          biometric == null ||
          !await biometric!.authenticate('Bekräfta för att låsa upp Quee med fingeravtryck')) {
        return false;
      }
      await _store.write(_kBiometric, '1');
    } else {
      await _store.delete(_kBiometric);
    }
    _useBiometric = on;
    notifyListeners();
    return true;
  }

  /// The unlock screen's fingerprint try. Wrong PIN tries are not touched.
  Future<bool> unlockWithBiometric() async => biometricEnabled && await biometric!.authenticate('Lås upp Quee');

  /// How many digits the PIN has, so the unlock screen can check by itself.
  int get pinLength => _length;

  Future<void> load() async {
    _enabled = await _store.read(_kHash) != null;
    _length = int.tryParse(await _store.read(_kLength) ?? '') ?? minLength;
    _useBiometric = await _store.read(_kBiometric) == '1';
  }

  Future<void> setPin(String pin) async {
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    await _store.write(_kSalt, base64Encode(salt));
    await _store.write(_kHash, base64Encode(await hash(pin, salt)));
    await _store.write(_kLength, '${pin.length}');
    await _store.write(_kFails, '0');
    await _store.delete(_kUntil);
    _enabled = true;
    _length = pin.length;
    notifyListeners();
  }

  Future<PinResult> verify(String pin) async {
    final now = _now();
    final until = DateTime.tryParse(await _store.read(_kUntil) ?? '');
    if (until != null && until.isAfter(now)) return PinResult(PinStatus.locked, wait: until.difference(now));
    final salt = await _store.read(_kSalt);
    final stored = await _store.read(_kHash);
    if (salt == null || stored == null) return const PinResult(PinStatus.ok);
    final candidate = await hash(pin, base64Decode(salt));
    if (_same(candidate, base64Decode(stored))) {
      await _store.write(_kFails, '0');
      await _store.delete(_kUntil);
      return const PinResult(PinStatus.ok);
    }
    final fails = (int.tryParse(await _store.read(_kFails) ?? '') ?? 0) + 1;
    await _store.write(_kFails, '$fails');
    final wait = lockoutFor(fails);
    if (wait > Duration.zero) {
      await _store.write(_kUntil, now.add(wait).toIso8601String());
      return PinResult(PinStatus.locked, wait: wait);
    }
    return PinResult(PinStatus.wrong, triesLeft: freeTries - fails);
  }

  Future<void> clear() async {
    for (final k in const [_kHash, _kSalt, _kLength, _kFails, _kUntil, _kBiometric]) {
      await _store.delete(k);
    }
    _enabled = false;
    _useBiometric = false;
    notifyListeners();
  }

  /// Waiting after the [fails]th wrong try in a row: none for the first
  /// [freeTries] - 1, then 30 s, 1 min, 5 min, 15 min and 1 h from then on.
  static Duration lockoutFor(int fails) {
    if (fails < freeTries) return Duration.zero;
    const seconds = [30, 60, 300, 900, 3600];
    return Duration(seconds: seconds[min(fails - freeTries, seconds.length - 1)]);
  }

  static Future<List<int>> hash(String pin, List<int> salt) =>
      Isolate.run(() async => (await _derive(pin, salt)).extractBytes());

  static Future<SecretKey> _derive(String pin, List<int> salt) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: _iterations, bits: 256)
          .deriveKeyFromPassword(password: pin, nonce: salt);

  /// Compares without stopping at the first difference.
  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
