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

  PackageData withIssues(List<PackageItem> items) => PackageData(
        ReportPeriod.containing(PeriodKind.month, DateTime(2026, 10, 15), 1),
        const BusinessProfile(name: 'Pub AB'),
        null,
        items,
        true,
        issues: const [ReviewIssue('Z-rapport saknas för 2026-10-03', IssueTarget.none), ReviewIssue('Nassim: fyll i datum', IssueTarget.none)],
      );

  test('status: ready, open, then accepted by the owner', () {
    expect(_data([fine]).status, PackageStatus.ready);
    final d = withIssues([fine, yellow]);
    expect(d.status, PackageStatus.open);
    expect(packageStatusText(d), '2 saker att se över');
    d.accepted.add('k');
    expect(d.status, PackageStatus.accepted);
    expect(packageStatusText(d), 'Klart, med 2 punkter som ägaren har godkänt');
  });

  test('an empty period has its own status', () {
    final d = PackageData(
        ReportPeriod.containing(PeriodKind.month, DateTime(2026, 10, 15), 1), const BusinessProfile(), null, [empty], false);
    expect(d.status, PackageStatus.empty);
  });

  test('"Att känna till" goes into the package when there are open points, and follows the confirmation', () {
    final d = withIssues([fine, yellow]);
    expect(packageContents(d).map((i) => i.id), ['a', 'attkanna']);
    expect(d.issuesItem!.table!.rows.map((r) => r[1]), ['Öppen', 'Öppen']);
    d.accepted.add('k');
    expect(d.issuesItem!.table!.rows.map((r) => r[1]), ['Godkänd av ägaren', 'Godkänd av ägaren']);
    expect(_data([fine]).issuesItem, isNull);
    expect(packageContents(_data([fine])).map((i) => i.id), ['a']);
  });

  test('the mail text lists the open points, and says so when the owner confirmed them', () {
    final d = withIssues([fine, yellow]);
    final open = packageMailBody(d, greeting: 'Anna', ownerEmail: 'a@b.se');
    expect(open, contains('Hej Anna!'));
    expect(open, contains('Det här är inte klart ännu:'));
    expect(open, contains('- Z-rapport saknas för 2026-10-03'));
    d.accepted.add('k');
    expect(packageMailBody(d, greeting: '', ownerEmail: ''), contains('skickar underlaget som det är'));
    expect(packageMailBody(_data([fine]), greeting: '', ownerEmail: ''), contains('Allt ser komplett ut.'));
  });

  test('the README carries the status, the points and the owner\'s message', () {
    final d = withIssues([fine, yellow]);
    final r = packageReadme(d, message: 'Hej!\nFaktura kommer.');
    expect(r, contains('Status: 2 saker att se över'));
    expect(r, contains('- Nassim: fyll i datum'));
    expect(r, contains('Meddelande från ägaren:\r\nHej!\r\nFaktura kommer.'));
    expect(packageReadme(_data([fine])), isNot(contains('Meddelande')));
  });

  test('when the problem is fixed the item is normal again, no confirmation needed', () {
    const fixed = PackageItem(id: 'k', title: 'Kontrollrapport', detail: 'Allt ser bra ut');
    expect(packageContents(_data([fixed])).map((i) => i.id), ['k']);
  });
}
