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

void main() {
  late _MemoryStore store;
  late DateTime clock;
  late PinLock lock;

  setUp(() async {
    store = _MemoryStore();
    clock = DateTime(2026, 11, 11, 12);
    lock = PinLock(store, now: () => clock);
    await lock.load();
  });

  test('off until a PIN is set; the PIN itself is never stored', () async {
    expect(lock.enabled, isFalse);
    await lock.setPin('4821');
    expect(lock.enabled, isTrue);
    expect(lock.pinLength, 4);
    expect(store.values.values.any((v) => v.contains('4821')), isFalse);
  });

  test('the right PIN opens, a wrong one does not', () async {
    await lock.setPin('4821');
    expect((await lock.verify('4821')).status, PinStatus.ok);
    final wrong = await lock.verify('1234');
    expect(wrong.status, PinStatus.wrong);
    expect(wrong.triesLeft, 4);
  });

  test('five wrong tries start a wait that grows, and the right PIN waits too', () async {
    await lock.setPin('482193');
    for (var i = 0; i < 4; i++) {
      expect((await lock.verify('000000')).status, PinStatus.wrong);
    }
    final fifth = await lock.verify('000000');
    expect(fifth.status, PinStatus.locked);
    expect(fifth.wait, const Duration(seconds: 30));
    // During the wait even the right PIN is refused.
    expect((await lock.verify('482193')).status, PinStatus.locked);
    clock = clock.add(const Duration(seconds: 31));
    expect((await lock.verify('000000')).wait, const Duration(seconds: 60));
    clock = clock.add(const Duration(seconds: 61));
    expect((await lock.verify('482193')).status, PinStatus.ok);
  });

  test('the count and the wait survive closing the app', () async {
    await lock.setPin('4821');
    for (var i = 0; i < 5; i++) {
      await lock.verify('0000');
    }
    final reopened = PinLock(store, now: () => clock);
    await reopened.load();
    expect(reopened.enabled, isTrue);
    expect((await reopened.verify('4821')).status, PinStatus.locked);
  });

  test('a right PIN resets the count', () async {
    await lock.setPin('4821');
    await lock.verify('0000');
    await lock.verify('0000');
    expect((await lock.verify('4821')).status, PinStatus.ok);
    expect((await lock.verify('0000')).triesLeft, 4);
  });

  test('turning the lock off removes everything', () async {
    await lock.setPin('4821');
    await lock.clear();
    expect(lock.enabled, isFalse);
    expect(store.values, isEmpty);
  });

  test('waiting times', () {
    expect(PinLock.lockoutFor(4), Duration.zero);
    expect(PinLock.lockoutFor(5), const Duration(seconds: 30));
    expect(PinLock.lockoutFor(6), const Duration(minutes: 1));
    expect(PinLock.lockoutFor(7), const Duration(minutes: 5));
    expect(PinLock.lockoutFor(8), const Duration(minutes: 15));
    expect(PinLock.lockoutFor(9), const Duration(hours: 1));
    expect(PinLock.lockoutFor(40), const Duration(hours: 1));
  });

  test('the same PIN gives a different hash with another salt', () async {
    final a = await PinLock.hash('4821', List<int>.filled(16, 1));
    final b = await PinLock.hash('4821', List<int>.filled(16, 2));
    expect(a, isNot(b));
    expect(a.length, 32);
  });
}
