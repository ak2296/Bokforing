import 'package:bokforing/data/database.dart';
import 'package:bokforing/data/repository.dart';
import 'package:bokforing/domain/dates.dart';
import 'package:bokforing/domain/invoice_filter.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Invoice _inv({
  String date = '2026-11-03',
  String supplier = 'Centrumgrossisten AB',
  String number = '1001',
  int total = 52100,
  int vat = 2947,
  String type = 'varuinkop',
  bool noVat = false,
}) =>
    Invoice(
      invoiceDate: date,
      supplier: supplier,
      invoiceNumber: number,
      total: Money(total),
      vatTotal: Money(vat),
      costType: type,
      noVat: noVat,
      meta: const RecordMeta(source: RecordSource.manual),
    );

void main() {
  group('weeks', () {
    test('ISO week numbers as on Swedish calendars', () {
      expect(SwedishDates.isoWeek(DateTime(2026, 11, 10)), 46);
      expect(SwedishDates.isoWeek(DateTime(2026, 1, 1)), 1); // a Thursday
      expect(SwedishDates.isoWeek(DateTime(2027, 1, 1)), 53); // Friday, still week 53 of 2026
      expect(SwedishDates.isoWeek(DateTime(2024, 12, 30)), 1); // Monday of week 1, 2025
      expect(SwedishDates.isoWeek(DateTime(2026, 7, 1)), 27); // summer time
    });

    test('Monday of the week', () {
      expect(SwedishDates.mondayOf(DateTime(2026, 11, 10)), DateTime(2026, 11, 9));
      expect(SwedishDates.mondayOf(DateTime(2026, 11, 15)), DateTime(2026, 11, 9)); // Sunday
      expect(SwedishDates.mondayOf(DateTime(2026, 11, 9)), DateTime(2026, 11, 9));
    });
  });

  group('missing fields', () {
    test('a complete invoice', () => expect(_inv().missingFields, isEmpty));

    test('each missing field is named', () {
      expect(_inv(type: '').missingFields, ['kostnadstyp']);
      expect(_inv(supplier: ' ').missingFields, ['leverantör']);
      expect(_inv(total: 0, vat: 0).missingFields, ['belopp', 'moms']);
    });

    test('0 kr moms is fine only when confirmed', () {
      expect(_inv(vat: 0).missingFields, ['moms']);
      expect(_inv(vat: 0, noVat: true).missingFields, isEmpty);
    });
  });

  group('filter', () {
    final list = [
      _inv(),
      _inv(supplier: 'Willys', number: 'K-77', type: 'forbrukning', date: '2026-10-02'),
      _inv(supplier: 'Lunds Universitet', number: '', type: '', vat: 0, date: '2026-09-15'),
    ];
    List<String> hits(InvoiceFilter f) => list.where(f.matches).map((i) => i.supplier).toList();

    test('free text matches supplier, number and cost type', () {
      expect(hits(const InvoiceFilter(query: 'willys')), ['Willys']);
      expect(hits(const InvoiceFilter(query: 'k-77')), ['Willys']);
      expect(hits(const InvoiceFilter(query: 'varuinköp')), ['Centrumgrossisten AB']);
      expect(hits(const InvoiceFilter(query: 'centrum 1001')), ['Centrumgrossisten AB']);
    });

    test('supplier, cost type and dates', () {
      expect(hits(const InvoiceFilter(supplier: 'WILLYS')), ['Willys']);
      expect(hits(const InvoiceFilter(costType: '')), ['Lunds Universitet']);
      expect(hits(const InvoiceFilter(from: '2026-10-01', to: '2026-10-31')), ['Willys']);
      expect(hits(const InvoiceFilter(from: '2026-10-01')), ['Centrumgrossisten AB', 'Willys']);
    });

    test('active', () {
      expect(const InvoiceFilter().active, isFalse);
      expect(const InvoiceFilter(query: '  ').active, isFalse);
      expect(const InvoiceFilter(costType: '').active, isTrue);
      expect(const InvoiceFilter(supplier: 'X').copyWith(clearSupplier: true).active, isFalse);
    });
  });

  test('"Ingen moms" is saved and read back', () async {
    sqfliteFfiInit();
    final db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
    final repo = Repository(db);
    final id = await repo.saveInvoice(_inv(vat: 0, noVat: true));
    final back = await repo.invoice(id);
    expect(back!.noVat, isTrue);
    expect(back.isIncomplete, isFalse);
    await db.close();
  });
}
