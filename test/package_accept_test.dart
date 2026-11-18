import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/report_period.dart';
import 'package:bokforing/export/redovisar_package.dart';
import 'package:flutter_test/flutter_test.dart';

PackageData _data(List<PackageItem> items) => PackageData(
      ReportPeriod.containing(PeriodKind.month, DateTime(2026, 10, 15), 1),
      const BusinessProfile(),
      null,
      items,
      true,
    );

void main() {
  const fine = PackageItem(id: 'a', title: 'A', detail: '');
  const yellow = PackageItem(id: 'k', title: 'Kontrollrapport', detail: '1 sak', problem: 'Se över');
  const empty = PackageItem(id: 'e', title: 'E', detail: '', problem: 'Tom');
  const left = PackageItem(id: 'b', title: 'Balans', detail: '', problem: 'Fyll i', included: false);

  test('a yellow item goes into the package only after the owner confirmed it', () {
    final d = _data([fine, yellow, empty, left]);
    expect(packageContents(d).map((i) => i.id), ['a']);
    d.accepted.addAll(['k', 'b']);
    expect(packageContents(d).map((i) => i.id), ['a', 'k']);
  });

  test('an item left out (missing balances) stays out even when accepted', () {
    final d = _data([left])..accepted.add('b');
    expect(packageContents(d), isEmpty);
  });

  test('when the problem is fixed the item is normal again, no confirmation needed', () {
    const fixed = PackageItem(id: 'k', title: 'Kontrollrapport', detail: 'Allt ser bra ut');
    expect(packageContents(_data([fixed])).map((i) => i.id), ['k']);
  });
}
