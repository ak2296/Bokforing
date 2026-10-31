import 'package:bokforing/data/database.dart';
import 'package:bokforing/data/repository.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/reports.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:bokforing/export/backup.dart';
import 'package:bokforing/export/monthly_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  Future<Repository> seeded() async {
    final repo = Repository(await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
    await repo.saveProfile(const BusinessProfile(name: 'Twins Pub och Pizza'));
    await repo.saveCategories(const [
      Category(name: 'Mat', vat: VatRate.six),
      Category(name: 'Öl', vat: VatRate.twentyFive),
    ]);
    final cats = await repo.categories();
    await repo.saveDailySales(DailySales(
      businessDate: '2026-10-28',
      reportedTotal: Money.kr(1310),
      items: [
        SalesItem(categoryId: cats[0].id, categoryName: 'Mat', vat: VatRate.six, amount: Money.kr(1060)),
        SalesItem(categoryId: cats[1].id, categoryName: 'Öl', vat: VatRate.twentyFive, amount: Money.kr(250)),
      ],
      meta: const RecordMeta(source: RecordSource.manual),
    ));
    await repo.saveInvoice(Invoice(
      invoiceDate: '2026-10-28',
      supplier: 'Grossisten AB',
      total: Money.kr(1250),
      vatTotal: Money.kr(250),
      meta: const RecordMeta(source: RecordSource.manual),
    ));
    return repo;
  }

  test('backup round trip restores all records, wrong password is rejected', () async {
    final repo = await seeded();
    final bytes = await Backup.encrypt(await Backup.collect(repo.db), 'hemligt-lösenord');
    expect(String.fromCharCodes(bytes), isNot(contains('Grossisten')));

    await expectLater(Backup.decrypt(bytes, 'fel-lösenord'), throwsA(isA<BackupException>()));

    await repo.deleteInvoice((await repo.invoicesBetween('2026-10-01', '2026-10-31')).single.id!);
    expect(await repo.invoicesBetween('2026-10-01', '2026-10-31'), isEmpty);

    final backup = await Backup.decrypt(bytes, 'hemligt-lösenord');
    await Backup.restore(repo.db, backup);
    final invoices = await repo.invoicesBetween('2026-10-01', '2026-10-31');
    expect(invoices.single.supplier, 'Grossisten AB');
    expect((await repo.dailySalesBetween('2026-10-01', '2026-10-31')).single.detailedTotal, Money.kr(1310));
    expect((await repo.profile()).name, 'Twins Pub och Pizza');
    expect(Backup.summary(backup), contains('Fakturor: 1'));
    await repo.db.close();
  });

  test('monthly PDF is generated with dynamic columns', () async {
    final repo = await seeded();
    final report = const ReportGenerator().monthly(
      year: 2026,
      month: 10,
      categories: await repo.categories(includeInactive: true),
      sales: await repo.dailySalesBetween('2026-10-01', '2026-10-31'),
      invoices: await repo.invoicesBetween('2026-10-01', '2026-10-31'),
    );
    final pdf = await buildMonthlyPdf(report, await repo.profile(), createdAt: DateTime(2026, 10, 31));
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    expect(pdf.length, greaterThan(1000));
    await repo.db.close();
  });
}
