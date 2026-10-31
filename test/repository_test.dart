import 'package:bokforing/data/database.dart';
import 'package:bokforing/data/repository.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Repository repo;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    final db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    repo = Repository(db);
  });

  tearDown(() => repo.db.close());

  test('default VAT rates', () async {
    expect(await repo.vatRates(), [VatRate.zero, VatRate.six, VatRate.twelve, VatRate.twentyFive]);
  });

  test('categories: add, reorder, rename, deactivate', () async {
    await repo.saveCategories(const [
      Category(name: 'Mat', vat: VatRate.six),
      Category(name: 'Öl', vat: VatRate.twentyFive),
    ]);
    var cats = await repo.categories();
    expect(cats.map((c) => c.name), ['Mat', 'Öl']);

    await repo.saveCategories([cats[1], cats[0].copyWith(name: 'Mat (hämtmat)')]);
    cats = await repo.categories();
    expect(cats.map((c) => c.name), ['Öl', 'Mat (hämtmat)']);

    await repo.saveCategories([cats[0]]);
    expect((await repo.categories()).map((c) => c.name), ['Öl']);
    expect((await repo.categories(includeInactive: true)).length, 2);
  });

  test('remembered label mappings', () async {
    await repo.saveCategories(const [Category(name: 'Dryck', vat: VatRate.twentyFive)]);
    final id = (await repo.categories()).single.id!;
    await repo.rememberAlias('  Dryck   Avhämtning ', id);
    expect(await repo.categoryAliases(), {'dryck avhämtning': id});
  });

  test('daily sales: round trip, snapshot names, duplicates, audit trail', () async {
    await repo.saveCategories(const [Category(name: 'Mat', vat: VatRate.six)]);
    final cat = (await repo.categories()).single;
    final id = await repo.saveDailySales(DailySales(
      businessDate: '2026-10-28',
      zNumber: '123',
      reportedTotal: Money.kr(1060),
      items: [SalesItem(categoryId: cat.id, categoryName: 'Mat', vat: VatRate.six, amount: Money.kr(1060))],
      meta: const RecordMeta(source: RecordSource.ocr),
    ));
    final loaded = (await repo.dailySales(id))!;
    expect(loaded.items.single.amount, Money.kr(1060));
    expect(loaded.outputVat, Money.kr(60));
    expect(loaded.meta.confirmed, isTrue);

    await repo.saveCategories([cat.copyWith(name: 'Livsmedel', vat: VatRate.twelve)]);
    final again = (await repo.dailySales(id))!;
    expect(again.items.single.categoryName, 'Mat');
    expect(again.items.single.vat, VatRate.six);

    final dupes = await repo.findDuplicateDailySales(DailySales(
        businessDate: '2026-10-28',
        zNumber: '123',
        reportedTotal: Money.kr(1060),
        items: const [],
        meta: const RecordMeta(source: RecordSource.manual)));
    expect(dupes.length, 1);

    await repo.deleteDailySales(id);
    expect(await repo.dailySales(id), isNull);
    final audit = await repo.auditFor('daily_sales', id);
    expect(audit.map((a) => a['action']), ['create', 'delete']);
  });

  test('invoices: VAT lines, duplicates, month query', () async {
    final inv = Invoice(
      invoiceDate: '2026-10-28',
      supplier: 'Example AB',
      invoiceNumber: 'F-1001',
      total: Money.kr(1250),
      vatTotal: Money.kr(250),
      vatLines: [InvoiceVatLine(rate: VatRate.twentyFive, vat: Money.kr(250), net: Money.kr(1000))],
      meta: const RecordMeta(source: RecordSource.ocr),
    );
    final id = await repo.saveInvoice(inv);
    final loaded = (await repo.invoice(id))!;
    expect(loaded.vatLines.single.net, Money.kr(1000));
    expect((await repo.findDuplicateInvoices(inv)).length, 1);
    final other = Invoice(
        invoiceDate: '2026-10-29',
        supplier: 'Annat AB',
        invoiceNumber: 'X',
        total: Money.kr(5),
        vatTotal: Money.zero,
        meta: const RecordMeta(source: RecordSource.manual));
    expect((await repo.findDuplicateInvoices(other)).length, 0);
    expect((await repo.invoicesBetween('2026-10-01', '2026-10-31')).length, 1);
    expect((await repo.invoicesBetween('2026-11-01', '2026-11-30')).length, 0);
    final recent = await repo.recentRegistrations();
    expect(recent.single.typeLabel, 'Faktura');
    expect(await repo.documentCount(), 1);
  });
}
