import 'package:bokforing/domain/invoice_parser.dart';
import 'package:bokforing/domain/invoice_prefs.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/validation.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:bokforing/domain/z_report_parser.dart';
import 'package:flutter_test/flutter_test.dart';

InvoiceDraft _inv(String text, [InvoicePrefs prefs = const InvoicePrefs()]) =>
    InvoiceParser(prefs: prefs).parse(OcrResult.fromPlainText(text));

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

  group('Field choices', () {
    const text = 'Faktura\nFakturadatum 2026-10-01\nFörfallodatum 2026-10-31\nBetalningsdatum 2026-10-20\n'
        'Summa 999,00\nBetalt belopp 1 250,00\nMoms 25% 250,00';

    test('the chosen date becomes the record date, others are offered', () {
      expect(_inv(text).date.value, '2026-10-01');
      expect(_inv(text, const InvoicePrefs(dateChoice: InvoiceDateChoice.dueDate)).date.value, '2026-10-31');
      final d = _inv(text, const InvoicePrefs(dateChoice: InvoiceDateChoice.paymentDate));
      expect(d.date.value, '2026-10-20');
      expect(d.dateOptions.map((o) => o.date), containsAll(['2026-10-01', '2026-10-31', '2026-10-20']));
    });

    test('switched-off labels are never used for the total', () {
      expect(_inv(text).total.value, Money.kr(1250));
      final onlySumma = _inv(text, const InvoicePrefs(totalLabels: {'summa'}));
      expect(onlySumma.total.value, Money.kr(999));
    });

    test('VAT labels can be switched off', () {
      final d = _inv('Faktura\nMomsbelopp 250,00\nAtt betala 1 250,00', const InvoicePrefs(vatLabels: {'moms'}));
      expect(d.vatTotal.value, isNull);
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
