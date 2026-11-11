import 'package:bokforing/app/biometric.dart';
import 'package:bokforing/app/pin_lock.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements LockStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _Fake implements BiometricAuth {
  bool sensor = true;
  bool accepts = true;
  int asked = 0;
  @override
  Future<bool> available() async => sensor;
  @override
  Future<bool> authenticate(String reason) async {
    asked++;
    return accepts;
  }
}

void main() {
  late _MemoryStore store;
  late _Fake fake;
  late PinLock lock;

  setUp(() async {
    store = _MemoryStore();
    fake = _Fake();
    lock = PinLock(store, biometric: fake);
    await lock.load();
  });

  test('off by default and impossible without a PIN', () async {
    expect(lock.biometricEnabled, isFalse);
    expect(await lock.setBiometric(true), isFalse);
    expect(lock.biometricEnabled, isFalse);
  });

  test('turning it on asks for the fingerprint once and is remembered', () async {
    await lock.setPin('4821');
    expect(await lock.setBiometric(true), isTrue);
    expect(fake.asked, 1);
    expect(lock.biometricEnabled, isTrue);
    final again = PinLock(store, biometric: fake);
    await again.load();
    expect(again.biometricEnabled, isTrue);
  });

  test('a failed check leaves it off', () async {
    await lock.setPin('4821');
    fake.accepts = false;
    expect(await lock.setBiometric(true), isFalse);
    expect(lock.biometricEnabled, isFalse);
  });

  test('unlocking follows the fingerprint, wrong PIN tries are untouched', () async {
    await lock.setPin('4821');
    await lock.setBiometric(true);
    expect(await lock.unlockWithBiometric(), isTrue);
    fake.accepts = false;
    expect(await lock.unlockWithBiometric(), isFalse);
    expect((await lock.verify('1111')).triesLeft, PinLock.freeTries - 1);
  });

  test('turning the PIN off turns the fingerprint off', () async {
    await lock.setPin('4821');
    await lock.setBiometric(true);
    await lock.clear();
    expect(lock.biometricEnabled, isFalse);
    expect(store.values, isEmpty);
    expect(await lock.unlockWithBiometric(), isFalse);
  });

  test('no sensor: not offered', () async {
    fake.sensor = false;
    expect(await lock.biometricAvailable, isFalse);
  });
}
