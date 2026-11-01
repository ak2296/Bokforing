import 'package:bokforing/data/database.dart';
import 'package:bokforing/data/repository.dart';
import 'package:bokforing/domain/invoice_parser.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/payment_detector.dart';
import 'package:bokforing/notify/reminders.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

PaymentDetection _detect(String text, {double? aspect}) =>
    const PaymentDetector().detect(text.split('\n'), paperAspect: aspect);

void main() {
  group('Kvitto or faktura', () {
    test('a card receipt without the word kvitto is a paid receipt', () {
      final d = _detect('WILLYS\nTotalt 598,90 SEK\nMottaget Kontokort 598,90\nKortnr ****1234\nGodkänd\n14:32',
          aspect: 3.1);
      expect(d.kind, PaymentKind.kvitto);
      expect(d.paid, isTrue);
      expect(d.isCertain, isTrue);
    });

    test('an invoice with due date and bankgiro is unpaid', () {
      final d = _detect('FAKTURA\nFakturanummer 1001\nFörfallodatum 2026-11-30\nBankgiro 123-4567\nOCR 1234567890\nAtt betala 1 250,00',
          aspect: 1.41);
      expect(d.kind, PaymentKind.faktura);
      expect(d.paid, isFalse);
    });

    test('an invoice stamped BETALD is paid', () {
      final d = _detect('FAKTURA\nFakturanr 778812\nFörfallodatum 2026-11-14\nAtt betala SEK 521,00\nBETALD');
      expect(d.kind, PaymentKind.faktura);
      expect(d.paid, isTrue);
    });

    test('too few signals: unknown, the user decides', () {
      final d = _detect('Butiken\nSumma 120,00');
      expect(d.kind, PaymentKind.unknown);
      expect(d.isCertain, isFalse);
    });
  });

  test('bankgiro and plusgiro are read from the invoice', () {
    final d = const InvoiceParser().parse(OcrResult.fromPlainText(
        'FAKTURA\nBankgiro: 5050-1055\nPlusgiro 12 34 56-7\nFörfallodatum 2026-11-30\nAtt betala 100,00'));
    expect(d.bankgiro.value, '5050-1055');
    expect(d.plusgiro.value, '123456-7');
    expect(d.payment!.kind, PaymentKind.faktura);
  });

  test('reminders: days before and on the due date, only in the future, only unpaid', () {
    final inv = Invoice(
        id: 7,
        invoiceDate: '2026-11-01',
        dueDate: '2026-11-20',
        total: Money.kr(100),
        vatTotal: Money.zero,
        meta: const RecordMeta(source: RecordSource.manual));
    final now = DateTime(2026, 11, 1, 12);
    expect(Reminders.times(inv, 3, now), [DateTime(2026, 11, 17, 9), DateTime(2026, 11, 20, 9)]);
    expect(Reminders.times(inv, 3, DateTime(2026, 11, 18, 12)), [DateTime(2026, 11, 20, 9)]);
    expect(Reminders.times(inv.copyWith(paid: true), 3, now), isEmpty);
  });

  test('paid status, unpaid list and supplier memory are stored', () async {
    sqfliteFfiInit();
    final repo = Repository(await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
    Invoice inv(String supplier, String? due, {bool paid = false}) => Invoice(
        invoiceDate: '2026-11-01',
        supplier: supplier,
        dueDate: due,
        total: Money.kr(100),
        vatTotal: Money.kr(20),
        bankgiro: '123-4567',
        paid: paid,
        paidDate: paid ? '2026-11-01' : null,
        meta: const RecordMeta(source: RecordSource.manual));
    final later = await repo.saveInvoice(inv('B AB', '2026-11-30'));
    final soon = await repo.saveInvoice(inv('A AB', '2026-11-10'));
    await repo.saveInvoice(inv('Willys', null, paid: true));
    final unpaid = await repo.unpaidInvoices();
    expect(unpaid.map((i) => i.id), [soon, later]);
    expect(unpaid.first.bankgiro, '123-4567');

    await repo.setInvoicePaid(soon, paid: true, paidDate: '2026-11-09');
    final paid = (await repo.invoice(soon))!;
    expect(paid.paid, isTrue);
    expect(paid.paidDate, '2026-11-09');
    expect((await repo.unpaidInvoices()).single.id, later);
    expect((await repo.auditFor('invoice', soon)).map((a) => a['action']), ['create', 'paid']);
    await repo.db.close();
  });
}
