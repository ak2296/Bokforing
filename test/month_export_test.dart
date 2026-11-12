import 'package:bokforing/domain/cost_types.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/reports.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:bokforing/export/table_export.dart';
import 'package:flutter_test/flutter_test.dart';

MonthlyReport _october() => const ReportGenerator().monthly(
      year: 2026,
      month: 10,
      categories: const [],
      sales: [
        DailySales(
          businessDate: '2026-10-05',
          reportedTotal: Money.kr(1000),
          items: [SalesItem(categoryName: 'Mat', vat: VatRate.twelve, amount: Money.kr(1000))],
          meta: const RecordMeta(source: RecordSource.manual),
        ),
      ],
      invoices: const [],
    );

void main() {
  test('the app view only has the day with an entry', () {
    expect(_october().rows.map((r) => r.date), ['2026-10-05']);
  });

  test('the export has every day of the month, empty days as zeros', () {
    final days = _october().exportRows;
    expect(days, hasLength(31));
    expect(days.first.date, '2026-10-01');
    expect(days.last.date, '2026-10-31');
    expect(days[4].sales, Money.kr(1000));
    expect(days[0].sales, Money.zero);
    expect(days[0].expenses, Money.zero);
  });

  test('Excel/PDF table: 31 rows, a zero day has zero in every cell', () {
    final t = monthlyTable(_october());
    expect(t.rows, hasLength(31));
    final empty = t.rows.first;
    expect(empty.first, '2026-10-01');
    expect(empty.skip(1).every((c) => c == '0,00'), isTrue);
    expect(t.rows[4][1], '1000,00');
  });

  test('February in a leap year has 29 days', () {
    final r = const ReportGenerator().monthly(
        year: 2028, month: 2, categories: const [], sales: const [], invoices: const []);
    expect(r.exportRows, hasLength(29));
  });

  test('alarm and surveillance has its own cost type', () {
    expect(CostType.byKey('larm'), CostType.security);
    expect(CostType.security.account, 5090);
    expect(CostType.all.where((c) => c.key == 'larm'), hasLength(1));
  });
}
