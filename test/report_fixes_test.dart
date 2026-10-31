import 'package:bokforing/domain/classifier.dart';
import 'package:bokforing/domain/invoice_parser.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/text_patterns.dart';
import 'package:bokforing/domain/validation.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:bokforing/domain/z_report_parser.dart';
import 'package:flutter_test/flutter_test.dart';

InvoiceDraft _inv(String text) => const InvoiceParser().parse(OcrResult.fromPlainText(text));

const _cats = [
  Category(id: 1, name: 'Mat', vat: VatRate.six),
  Category(id: 2, name: 'Vin', vat: VatRate.twentyFive),
];

void main() {
  group('Momspliktigt belopp is never a total', () {
    test('"Summa momspl. belopp" is not the total', () {
      final d = _inv('Faktura\nSumma momspl. belopp 1 000,00\nMoms 25% 250,00\nAtt betala 1 250,00');
      expect(d.total.value, Money.kr(1250));
      expect(d.totalCandidates.map((c) => c.value), isNot(contains(Money.kr(1000))));
    });
  });

  group('Kreditnota', () {
    test('amounts become negative even when printed without minus', () {
      final d = _inv('KREDITNOTA\nKreditfaktura nr 55\nMoms 25% 50,00\nAtt betala 250,00');
      expect(d.isCredit, isTrue);
      expect(d.total.value, Money.kr(-250));
      expect(d.vatTotal.value, Money.kr(-50));
      expect(d.vatLines.single.vat, Money.kr(-50));
    });

    test('printed minus amounts are accepted', () {
      final d = _inv('Kreditnota\nTotalt -1 250,00\nVarav moms -250,00');
      expect(d.total.value, Money.kr(-1250));
      expect(d.vatTotal.value, Money.kr(-250));
    });

    test('a negative total passes validation and reduces totals', () {
      final inv = Invoice(
          invoiceDate: '2026-10-28', total: Money.kr(-250), vatTotal: Money.kr(-50), meta: const RecordMeta(source: RecordSource.ocr));
      final results = const AccountingValidationEngine().validateInvoice(inv);
      expect(results.where((r) => r.status == ValidationStatus.error), isEmpty);
      expect(const AccountingValidationEngine().checkVatPlausible(Money.kr(50), Money.kr(-250)), isNotNull);
    });
  });

  group('Amount paid and VAT under different names', () {
    const text = 'Faktura\nFakturadatum 2026-10-01\nFörfallodatum 2026-10-31\nBetalningsdatum 2026-10-20\n'
        'Summa 999,00\nBetalt belopp 1 250,00\nMoms 25% 250,00';

    test('invoice date is used, every labelled date is offered', () {
      final d = _inv(text);
      expect(d.date.value, '2026-10-01');
      expect(d.dueDate.value, '2026-10-31');
      expect(d.dateOptions.map((o) => o.date), containsAll(['2026-10-01', '2026-10-31', '2026-10-20']));
    });

    test('Betalt belopp ranks above Summa', () {
      expect(_inv(text).total.value, Money.kr(1250));
    });

    test('Brutto and Momsbelopp', () {
      final d = _inv('Kvitto\nBrutto 125,00\nMomsbelopp 25,00');
      expect(d.total.value, Money.kr(125));
      expect(d.vatTotal.value, Money.kr(25));
    });

    test('Mervärdesskatt', () {
      final d = _inv('Faktura\nMervärdesskatt 50,00\nAtt betala 250,00');
      expect(d.vatTotal.value, Money.kr(50));
    });
  });

  group('English invoices and receipts', () {
    test('Amount due, VAT line, net excluded, English dates', () {
      final d = _inv('INVOICE\nInvoice number: INV-2041\nInvoice date: 28 Oct 2026\nDue date: Nov 27, 2026\n'
          'Subtotal (excl. VAT) 1,000.00\nVAT 25% 250.00\nAmount due 1,250.00');
      expect(d.total.value, Money.kr(1250));
      expect(d.total.confidence, Confidence.high);
      expect(d.vatTotal.value, Money.kr(250));
      expect(d.net, Money.kr(1000));
      expect(d.date.value, '2026-10-28');
      expect(d.dueDate.value, '2026-11-27');
      expect(d.invoiceNumber.value, 'INV-2041');
    });

    test('receipt: cash and change are not the total', () {
      final d = _inv('RECEIPT\nTotal 80.00\nCash 100.00\nChange 20.00\nTotal VAT 16.00');
      expect(d.total.value, Money.kr(80));
      expect(d.vatTotal.value, Money.kr(16));
    });

    test('Total incl. VAT and Amount paid', () {
      expect(_inv('Receipt\nTotal incl. VAT 125.00\nVAT amount 25.00').total.value, Money.kr(125));
      expect(_inv('Receipt\nAmount paid 640.00\nPaid by card 640.00').total.value, Money.kr(640));
    });

    test('a VAT registration number is not VAT', () {
      final d = _inv('Invoice\nVAT reg. no SE556677889901\nTotal 200.00');
      expect(d.vatTotal.value, isNull);
    });
  });

  group('Document type', () {
    test('a receipt titled Kvitto is an invoice, an English invoice too', () {
      const c = DocumentClassifier();
      expect(c.classify('ICA Nära\nKvitto\nTotalt 120,00\nKontokort 120,00\nMoms 25% 24,00 Netto 96,00').type,
          DocumentType.invoice);
      expect(c.classify('INVOICE\nInvoice number 12\nDue date 2026-11-27\nAmount due 1,250.00\nVAT 250.00').isCertain,
          isTrue);
    });
  });

  group('Supplier', () {
    test('label "Leverantör:" and a cut-off label', () {
      expect(_inv('Faktura\nLeverantör: EVRY\nAtt betala 10,00').supplier.value, 'EVRY');
      expect(_inv('ntor: EVRY\nFaktura\nAtt betala 10,00').supplier.value, 'EVRY');
      expect(_inv('INBETALNING/GIRERING AVI\nGrossisten AB\nAtt betala 10,00').supplier.value, 'Grossisten AB');
    });
  });

  group('Z-report dates and margins', () {
    test('the Från date of the period is the business date', () {
      final d = const ZReportParser(_cats).parse(OcrResult.fromPlainText(
          'Z-rapport\nUtskriven 2026-11-01 08:00\nFrån 2026-10-30 06:00 Till 2026-10-31 05:59\nVarugrupper\nMat 100,00\nTotal försäljning 100,00'));
      expect(d.date.value, '2026-10-30');
      expect(d.otherDates, isNot(contains('2026-11-01')));
    });

    test('company details are not sales rows', () {
      final d = const ZReportParser(_cats).parse(OcrResult.fromPlainText(
          'Z-rapport\nVarugrupper\nMat 100,00\nVin 89,00\nOrg nr 556677-2976\nhttps://onslip.com 360\nTotal försäljning 189,00'));
      expect(d.lines.map((l) => l.label), ['Mat', 'Vin']);
    });

    test('sideways text along the edge is ignored', () {
      final ocr = OcrResult(text: '', blocks: [
        OcrBlock('Mat 100,00', const OcrBox(100, 100, 400, 120), const [OcrLine('Mat 100,00', OcrBox(100, 100, 400, 120))]),
        OcrBlock('EJ KVITTO PÅ KÖP 2026-10-15', const OcrBox(5, 0, 25, 900),
            const [OcrLine('EJ KVITTO PÅ KÖP 2026-10-15', OcrBox(5, 0, 25, 900))]),
      ]);
      expect(ocr.rows().map((r) => r.text), ['Mat 100,00']);
    });
  });
}
