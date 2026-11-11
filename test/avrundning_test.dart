import 'package:bokforing/app/settings_keys.dart';
import 'package:bokforing/data/database.dart';
import 'package:bokforing/data/repository.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/reports.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Invoice _inv(int total, int vat, {String date = '2026-10-10', String supplier = 'Grossisten'}) => Invoice(
      invoiceDate: date,
      supplier: supplier,
      total: Money(total),
      vatTotal: Money(vat),
      costType: 'varuinkop',
      meta: const RecordMeta(source: RecordSource.manual),
    );

void main() {
  test('whole kronor, half away from zero', () {
    expect(const Money(1250).roundedToKr(), const Money(1300));
    expect(const Money(-1250).roundedToKr(), const Money(-1300));
    expect(const Money(1249).roundedToKr(), const Money(1200));
    expect(const Money(-1249).roundedToKr(), const Money(-1200));
    expect(const Money(49).roundedToKr(), Money.zero);
    expect(const Money(50).roundedToKr(), const Money(100));
    expect(const Money(9950).roundedToKr(), const Money(10000));
    expect(Money.zero.roundedToKr(), Money.zero);
  });

  test('a rounded invoice keeps everything else', () {
    final i = _inv(52134, 2947);
    final r = i.roundedToKr();
    expect(r.total, const Money(52100));
    expect(r.vatTotal, const Money(2900));
    expect(r.supplier, i.supplier);
    expect(r.invoiceDate, i.invoiceDate);
    expect(r.costType, i.costType);
    expect(r.paid, i.paid);
  });

  test('reports add up the rounded invoices, so the rows add up to the total', () {
    final list = [_inv(1040, 208), _inv(1040, 208)];
    MonthlyReport report(List<Invoice> inv) => const ReportGenerator()
        .monthly(year: 2026, month: 10, categories: const [], sales: const [], invoices: inv, online: const []);
    expect(report(list).totalExpenses, const Money(2080));
    final rounded = report([for (final i in list) i.roundedToKr()]);
    expect(rounded.totalExpenses, const Money(2000));
    expect(rounded.totalInputVat, const Money(400));
  });

  group('invoicesForReports', () {
    late Repository repo;
    setUpAll(sqfliteFfiInit);
    setUp(() async {
      repo = Repository(await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
      await repo.saveInvoice(_inv(52134, 2947));
    });
    tearDown(() => repo.db.close());

    test('exact while the switch is off', () async {
      final list = await repo.invoicesForReports('2026-10-01', '2026-10-31');
      expect(list.single.total, const Money(52134));
    });

    test('whole kronor when it is on, and the saved invoice is unchanged', () async {
      await repo.setBoolSetting(SettingsKeys.roundExpenses, true);
      final list = await repo.invoicesForReports('2026-10-01', '2026-10-31');
      expect(list.single.total, const Money(52100));
      expect(list.single.vatTotal, const Money(2900));
      final saved = await repo.invoicesBetween('2026-10-01', '2026-10-31');
      expect(saved.single.total, const Money(52134));
      expect(saved.single.vatTotal, const Money(2947));
    });
  });
}
