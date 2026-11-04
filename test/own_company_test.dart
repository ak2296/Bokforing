import 'package:bokforing/data/database.dart';
import 'package:bokforing/data/repository.dart';
import 'package:bokforing/domain/invoice_parser.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

InvoiceDraft _read(
  String text, {
  String name = 'Ankan restaurang & pizzeria',
  String org = '121212-1212',
  String address = 'Provvägen 12 A, 123 45 Malmö',
  List<String> saved = const [],
  List<String> known = const [],
}) =>
    InvoiceParser(ownName: name, ownOrgNumber: org, ownAddress: address, ownNames: saved, knownSuppliers: known)
        .parse(OcrResult.fromPlainText(text));

void main() {
  group('Own company on the paper', () {
    test('a name printed at the own address is no supplier and no question', () {
      final d = _read('TWINS   CENTRUMGROSSISTEN AB\nPROVVÄGEN 12   Kvarngatan 2\nAtt betala 320,00');
      expect(d.supplier.value, 'CENTRUMGROSSISTEN AB');
      expect(d.ownNameQuestion, isNull);
    });

    test('the same street with another number is the seller', () {
      final d = _read('Snabb AB\nLundavägen 150\nAtt betala 100,00');
      expect(d.supplier.value, 'Snabb AB');
      expect(d.ownNameQuestion, isNull);
    });

    test('a saved name is never the supplier, and is not asked about', () {
      final d = _read('TWINS\nGrossist AB\nAtt betala 100,00', saved: const ['TWINS']);
      expect(d.supplier.value, 'Grossist AB');
      expect(d.ownNameQuestion, isNull);
    });

    test('a close name with a seller: asked, Mitt företag already selected', () {
      final d = _read('Ankan Pizza AB\nGrossist AB\nAtt betala 100,00', org: '');
      expect(d.supplier.value, 'Grossist AB');
      expect(d.ownNameQuestion!.name, 'Ankan Pizza AB');
      expect(d.ownNameQuestion!.otherSupplier, 'Grossist AB');
      expect(d.ownNameQuestion!.assumeMine, isTrue);
    });

    test('a close name alone: asked, nothing selected', () {
      final d = _read('Ankan Pizza AB\nAtt betala 100,00');
      expect(d.supplier.value, 'Ankan Pizza AB');
      expect(d.ownNameQuestion!.otherSupplier, isNull);
      expect(d.ownNameQuestion!.assumeMine, isFalse);
    });

    test('a close name with its own org number is a supplier', () {
      final d = _read('Ankan Pizza AB\nOrg.nr 556123-4567\nAtt betala 100,00');
      expect(d.supplier.value, 'Ankan Pizza AB');
      expect(d.ownNameQuestion, isNull);
    });

    test('the own VAT number on the paper settles it without a question', () {
      final d = _read('Ankan Pizza AB\nGrossist AB\nErt momsnr SE121212121201\nAtt betala 100,00');
      expect(d.supplier.value, 'Grossist AB');
      expect(d.ownNameQuestion, isNull);
    });

    test('a name answered as supplier earlier is not asked again', () {
      final d = _read('Ankan Pizza AB\nAtt betala 100,00', known: const ['Ankan Pizza AB']);
      expect(d.supplier.value, 'Ankan Pizza AB');
      expect(d.ownNameQuestion, isNull);
    });

    test('a different name is the supplier, no question', () {
      final d = _read('Grossist AB\nAtt betala 100,00');
      expect(d.supplier.value, 'Grossist AB');
      expect(d.ownNameQuestion, isNull);
    });
  });

  test('company form, financial year and own names are stored and can change', () async {
    sqfliteFfiInit();
    final repo = Repository(await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
    expect(await repo.companyForm(), isNull);
    expect(await repo.fiscalStartMonth(), 1);
    expect(await repo.ownNames(), isEmpty);

    await repo.setCompanyForm(CompanyForm.enskildFirma);
    await repo.setCompanyForm(CompanyForm.aktiebolag);
    await repo.setFiscalStartMonth(7);
    await repo.addOwnName(' TWINS ');
    await repo.addOwnName('twins');
    await repo.addOwnName('Ankan pub');
    expect(await repo.companyForm(), CompanyForm.aktiebolag);
    expect(await repo.fiscalStartMonth(), 7);
    expect(await repo.ownNames(), ['TWINS', 'Ankan pub']);

    await repo.removeOwnName('TWINS');
    expect(await repo.ownNames(), ['Ankan pub']);
    await repo.db.close();
  });
}
