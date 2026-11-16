import 'package:bokforing/domain/report_period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a quarter, a half-year and a year hold the right dates and months', () {
    final d = DateTime(2026, 11, 16);
    final q = ReportPeriod.containing(PeriodKind.quarter, d, 1);
    expect(q.from, '2026-10-01');
    expect(q.to, '2026-12-31');
    expect(q.months, [(2026, 10), (2026, 11), (2026, 12)]);
    expect(q.title, 'Kvartal 4, okt–dec 2026');
    final h = ReportPeriod.containing(PeriodKind.half, d, 1);
    expect((h.from, h.to), ('2026-07-01', '2026-12-31'));
    expect(h.fileTag, '2026-H2');
    final y = ReportPeriod.containing(PeriodKind.year, d, 1);
    expect((y.from, y.to), ('2026-01-01', '2026-12-31'));
    expect(y.title, 'Året 2026');
    expect(y.fileTag, '2026');
  });

  test('stepping crosses the year and a broken financial year follows its start month', () {
    final q = ReportPeriod.containing(PeriodKind.quarter, DateTime(2026, 11, 16), 1);
    expect(q.step(1).from, '2027-01-01');
    expect(q.step(-4).from, '2025-10-01');
    // Financial year May to April: November 2026 is the third quarter, Nov-Jan.
    final b = ReportPeriod.containing(PeriodKind.quarter, DateTime(2026, 11, 16), 5);
    expect((b.from, b.to), ('2026-11-01', '2027-01-31'));
    expect(b.months, [(2026, 11), (2026, 12), (2027, 1)]);
    final fy = ReportPeriod.containing(PeriodKind.year, DateTime(2027, 2, 3), 5);
    expect((fy.from, fy.to), ('2026-05-01', '2027-04-30'));
    expect(fy.fileTag, '2026-2027');
  });

  test('changing the kind keeps the date and months stay in order', () {
    final m = ReportPeriod.containing(PeriodKind.month, DateTime(2026, 2, 10), 1);
    expect(m.title, 'Februari 2026');
    expect(m.inKind(PeriodKind.quarter).from, '2026-01-01');
    expect(m.inKind(PeriodKind.year).to, '2026-12-31');
    expect(m.step(-2).from, '2025-12-01');
  });
}
