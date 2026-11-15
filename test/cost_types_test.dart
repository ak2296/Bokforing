import 'package:bokforing/domain/cost_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => CostType.custom = const []);

  test('own cost types are saved, found and listed before Övriga', () {
    final mine = CostType.newCustom('Studentmedarbetare');
    CostType.custom = [mine];
    expect(CostType.byKey(mine.key)?.label, 'Studentmedarbetare');
    expect(CostType.labelFor(mine.key), 'Studentmedarbetare');
    expect(CostType.selectable.last, CostType.other);
    expect(CostType.selectable[CostType.selectable.length - 2], mine);
    final back = CostType.decodeCustom(CostType.encodeCustom(CostType.custom));
    expect(back.single.key, mine.key);
    expect(back.single.account, 6990);
  });

  test('a new own type never takes a key that is in use', () {
    final a = CostType.newCustom('Test');
    CostType.custom = [a];
    final b = CostType.newCustom('Test');
    expect(b.key, isNot(a.key));
  });

  test('the new standard types exist with BAS accounts', () {
    expect(CostType.byKey('medlemskap')?.label, 'Avgifter och medlemskap');
    expect(CostType.byKey('musik_tv')?.label, 'Musik och TV (licenser, abonnemang)');
  });

  test('a damaged saved list gives no types instead of a crash', () {
    expect(CostType.decodeCustom('not json'), isEmpty);
    expect(CostType.decodeCustom(null), isEmpty);
  });
}
