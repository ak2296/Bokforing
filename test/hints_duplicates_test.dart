import 'package:bokforing/data/database.dart';
import 'package:bokforing/data/repository.dart';
import 'package:bokforing/domain/invoice_parser.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/supplier_hints.dart';
import 'package:bokforing/domain/text_patterns.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _meta = RecordMeta(source: RecordSource.ocr);

/// A supplier whose total the rules miss: the amount stands after the
/// unusual label "Er skuld".
const _paper1 = '''
Grönsakshallen AB
Faktura
Fakturadatum   2026-10-01
Varor   1 200,00
Rabatt   -100,00
Er skuld   1 375,00
Moms   275,00''';

const _paper2 = '''
Grönsakshallen AB
Faktura
Fakturadatum   2026-11-01
Varor   800,00
Rabatt   -50,00
Er skuld   937,50
Moms   187,50''';

void main() {
  test('A label is learned from the value the user typed, and read on the next paper', () {
    final rows1 = _paper1.trim().split('\n');
    expect(SupplierHints.labelFor(rows1, HintField.total, '1375,00'), 'er skuld');
    expect(SupplierHints.read(_paper2.trim().split('\n'), HintField.total, 'er skuld'), '937,50');
    // A label under a row of labels: the same column above.
    final rows = ['Kundnr   Fakturanr   Datum', '1912   11519   2026-10-07'];
    expect(SupplierHints.labelFor(rows, HintField.number, '11519'), 'fakturanr');
    expect(SupplierHints.read(rows, HintField.number, 'fakturanr'), '11519');
  });

  test('A draft uses the learned label and marks the value "Kontrollera"', () {
    final draft = const InvoiceParser().parse(OcrResult.fromPlainText(_paper2));
    final hinted = draft.withHints(
        _paper2.trim().split('\n'), const [SupplierHint('gronsakshallen', HintField.total, 'er skuld', 2)]);
    expect(hinted.total.value, Money.parse('937,50'));
    expect(hinted.total.confidence, Confidence.medium);
    expect(hinted.notes.last, contains('rättade'));
  });

  test('Supplier keys ignore case, å/ä/ö and the company form', () {
    expect(SupplierHints.key('Grönsakshallen AB'), SupplierHints.key('GRONSAKSHALLEN'));
  });

  group('Repository', () {
    late Repository repo;
    setUpAll(sqfliteFfiInit);
    setUp(() async {
      final db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath);
      repo = Repository(db);
    });
    tearDown(() => repo.db.close());

    test('Learned labels are stored per supplier and counted', () async {
      await repo.learnHint('Grönsakshallen AB', HintField.total, 'er skuld');
      await repo.learnHint('GRÖNSAKSHALLEN', HintField.total, 'er skuld');
      final hints = await repo.supplierHints('Grönsakshallen');
      expect(hints.single.label, 'er skuld');
      expect(hints.single.hits, 2);
      await repo.forgetHint(hints.single.supplierKey, HintField.total);
      expect(await repo.supplierHints('Grönsakshallen AB'), isEmpty);
    });

    test('The same OCR number, or the same supplier and amount a few days apart, is a possible duplicate', () async {
      await repo.saveInvoice(const Invoice(
          invoiceDate: '2026-10-01',
          supplier: 'Vattenfall AB',
          total: Money(83876),
          vatTotal: Money(16775),
          ocrReference: '52300562919341',
          meta: _meta));
      // Same OCR, everything else misread.
      expect(
          await repo.findDuplicateInvoices(const Invoice(
              invoiceDate: '2026-01-10', supplier: 'Vatenfal', total: Money(1), vatTotal: Money.zero,
              ocrReference: '5230 0562 9193 41', meta: _meta)),
          hasLength(1));
      // Date misread by a few days, name written differently.
      expect(
          await repo.findDuplicateInvoices(const Invoice(
              invoiceDate: '2026-10-07', supplier: 'VATTENFALL', total: Money(83876), vatTotal: Money(16775), meta: _meta)),
          hasLength(1));
      // Another month's bill with the same amount is not flagged.
      expect(
          await repo.findDuplicateInvoices(const Invoice(
              invoiceDate: '2026-11-01', supplier: 'Vattenfall AB', total: Money(83876), vatTotal: Money(16775), meta: _meta)),
          isEmpty);
    });
  });
}
