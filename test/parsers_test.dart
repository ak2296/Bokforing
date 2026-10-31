import 'package:bokforing/domain/classifier.dart';
import 'package:bokforing/domain/invoice_parser.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/text_patterns.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:bokforing/domain/z_report_parser.dart';
import 'package:flutter_test/flutter_test.dart';

InvoiceDraft _invoice(String text) => const InvoiceParser().parse(OcrResult.fromPlainText(text));

const _cats = [
  Category(id: 1, name: 'Mat', vat: VatRate.six, sortOrder: 0),
  Category(id: 2, name: 'Mat avhämtning', vat: VatRate.six, sortOrder: 1),
  Category(id: 3, name: 'Dryck', vat: VatRate.twelve, sortOrder: 2),
  Category(id: 4, name: 'Sprit', vat: VatRate.twentyFive, sortOrder: 3),
  Category(id: 5, name: 'Tobak', vat: VatRate.twentyFive, sortOrder: 4),
  Category(id: 6, name: 'Vin', vat: VatRate.twentyFive, sortOrder: 5),
  Category(id: 7, name: 'Öl', vat: VatRate.twentyFive, sortOrder: 6),
];

void main() {
  group('TextPatterns', () {
    test('amounts skip dates, percentages and long numbers', () {
      final a = TextPatterns.amounts('2026-10-28 Moms 25% 250,00 OCR 123456789012');
      expect(a.map((t) => t.value), [Money.kr(250)]);
    });
    test('grouped thousands', () {
      expect(TextPatterns.amounts('Periodens försäljning kr 12 955,00').last.value, Money.kr(12955));
    });
    test('dates in several formats', () {
      expect(TextPatterns.dates('Datum 2026-10-28'), ['2026-10-28']);
      expect(TextPatterns.dates('28.10.2026 och 31/10/26'), ['2026-10-28', '2026-10-31']);
      expect(TextPatterns.dates('2026-02-30'), isEmpty);
    });
  });

  group('Classifier', () {
    test('invoice', () {
      final c = const DocumentClassifier().classify(
          'FAKTURA\nFakturanummer 1001\nFakturadatum 2026-10-28\nFörfallodatum 2026-11-27\nBankgiro 123-4567\nAtt betala 1 250,00');
      expect(c.type, DocumentType.invoice);
      expect(c.isCertain, isTrue);
    });
    test('Z-report', () {
      final c = const DocumentClassifier().classify(
          'Z-RAPPORT\nZ-nr 245\nDagens försäljning 10 800,00\nBetalningsmedel\nKontant 1 000,00\nKort 9 800,00\nVarugrupper');
      expect(c.type, DocumentType.zReport);
      expect(c.isCertain, isTrue);
    });
    test('too little evidence is unknown', () {
      final c = const DocumentClassifier().classify('Hej och välkommen tillbaka till oss');
      expect(c.type, DocumentType.unknown);
      expect(c.isCertain, isFalse);
    });
  });

  group('Invoice total is not the largest number', () {
    test('cash 100 and change 20 gives 80', () {
      final d = _invoice('Kvitto\nTotalt 80,00\nKontant 100,00\nVäxel 20,00');
      expect(d.total.value, Money.kr(80));
    });
    test('change without a total label is not recorded as total', () {
      final d = _invoice('Kvitto\nKontant 100,00\nVäxel 20,00');
      expect(d.total.value, isNull);
    });
    test('card paid: Totalt 800 and Betalt med kort 800', () {
      final d = _invoice('Kvitto\nTotalt 800,00\nBetalt med kort 800,00');
      expect(d.total.value, Money.kr(800));
    });
    test('Att betala wins over net and VAT', () {
      final d = _invoice('Faktura\nNetto 1 000,00\nMoms 25% 250,00\nAtt betala 1 250,00');
      expect(d.total.value, Money.kr(1250));
      expect(d.total.confidence, Confidence.high);
      expect(d.vatTotal.value, Money.kr(250));
      expect(d.net, Money.kr(1000));
    });
    test('Totalt inkl moms is a total', () {
      final d = _invoice('Kvitto\nTotalt inkl moms 125,00\nVarav moms 25,00');
      expect(d.total.value, Money.kr(125));
      expect(d.vatTotal.value, Money.kr(25));
    });
  });

  group('VAT', () {
    test('several rates: 250 + 120 + 60 = 430', () {
      final d = _invoice('Faktura\nMoms 25% 250,00\nMoms 12% 120,00\nMoms 6% 60,00\nAtt betala 3 430,00');
      expect(d.vatLines.map((l) => l.rate), [VatRate.twentyFive, VatRate.twelve, VatRate.six]);
      expect(d.vatTotal.value, Money.kr(430));
    });
    test('never invents VAT', () {
      final d = _invoice('Kvitto\nLunds universitet\nTotalt 200,00kr\nKortbetalning 200,00');
      expect(d.total.value, Money.kr(200));
      expect(d.vatTotal.value, isNull);
      expect(d.vatLines, isEmpty);
    });
    test('VAT reconstructed from printed net is marked calculated', () {
      final d = _invoice('Faktura\nSumma exkl. moms 1 000,00\nAtt betala 1 250,00');
      expect(d.vatTotal.value, Money.kr(250));
      expect(d.vatCalculated, isTrue);
    });
  });

  group('Real layouts from the owner', () {
    test('Willys receipt with VAT table', () {
      final d = _invoice('''
WILLYS
Kvitto
Totalt 598,90 SEK
Mottaget Kontokort 598,90
Moms% Moms Netto Brutto
6,00 31,05 517,95 549,00
25,00 9,98 39,92 49,90
2026-10-20 14:32''');
      expect(d.total.value, const Money(59890));
      expect(d.total.confidence, Confidence.high);
      expect(d.vatLines.length, 2);
      expect(d.vatLines[0].rate, VatRate.six);
      expect(d.vatLines[0].vat, const Money(3105));
      expect(d.vatLines[1].vat, const Money(998));
      expect(d.vatTotal.value, const Money(4103));
      expect(d.date.value, '2026-10-20');
    });

    test('Centrumgrossisten invoice', () {
      final d = _invoice('''
CENTRUMGROSSISTEN AB
FAKTURA
Fakturanr 778812
Kundnr 999
Fakturadatum Förfallodatum
2026-10-15 2026-11-14
Momspliktigt belopp 491,87
Moms 6% 29,47
Moms 25% 0,00
Öresutj. -0,34
Att betala SEK 521,00
BETALD''');
      expect(d.total.value, Money.kr(521));
      expect(d.vatTotal.value, const Money(2947));
      expect(d.vatLines.single.rate, VatRate.six);
      expect(d.net, const Money(49187));
      expect(d.date.value, '2026-10-15');
      expect(d.dueDate.value, '2026-11-14');
      expect(d.supplier.value, 'CENTRUMGROSSISTEN AB');
      expect(d.invoiceNumber.value, '778812');
    });
  });

  group('Z-report', () {
    const a4 = '''
Z-RAPPORT
Z-nr 245
Datum 2026-10-31
Periodens försäljning kr 12 955,00
Öresutjämning 0,00
Betalningar
Kort 11 000,00
Kontant 1 955,00
Försäljning per varugrupp
Dryck 163,00
Dryck avhämtning 70,00
Mat 1 912,00
Mat avhämtning 1 507,00
Sprit 880,00
Tobak 2 512,00
Vin 89,00
Öl 5 822,00
Försäljning per momsgrupp
Moms 25% 9 303,00
Grand total 1 234 567,00''';

    test('reads the per-category section and the total', () {
      final d = const ZReportParser(_cats).parse(OcrResult.fromPlainText(a4));
      expect(d.sectionFound, isTrue);
      expect(d.total.value, Money.kr(12955));
      expect(d.date.value, '2026-10-31');
      expect(d.zNumber.value, '245');
      expect(d.lines.length, 8);
      expect(Money.sum(d.lines.map((l) => l.amount)), Money.kr(12955));
    });

    test('exact names auto-assign, similar names only suggest', () {
      final d = const ZReportParser(_cats).parse(OcrResult.fromPlainText(a4));
      ZLine line(String label) => d.lines.firstWhere((l) => l.label == label);
      expect(line('Mat').categoryId, 1);
      expect(line('Mat').match, MatchKind.exact);
      expect(line('Mat avhämtning').categoryId, 2);
      expect(line('Dryck avhämtning').categoryId, isNull);
      expect(line('Dryck avhämtning').match, MatchKind.possible);
      expect(line('Dryck avhämtning').suggestedCategoryId, 3);
    });

    test('Mat avhämtning does not auto-match Mat', () {
      const cats = [Category(id: 1, name: 'Mat', vat: VatRate.twelve)];
      final d = const ZReportParser(cats).parse(OcrResult.fromPlainText(a4));
      final l = d.lines.firstWhere((l) => l.label == 'Mat avhämtning');
      expect(l.categoryId, isNull);
      expect(l.suggestedCategoryId, 1);
    });

    test('remembered mapping assigns automatically', () {
      final d = const ZReportParser(_cats, aliases: {'dryck avhämtning': 3}).parse(OcrResult.fromPlainText(a4));
      final l = d.lines.firstWhere((l) => l.label == 'Dryck avhämtning');
      expect(l.categoryId, 3);
      expect(l.match, MatchKind.remembered);
    });

    test('printed rate different from category rate is only a suggestion', () {
      final d = const ZReportParser(_cats)
          .parse(OcrResult.fromPlainText('Z-rapport\nDatum 2026-10-28\nVarugrupper\nMat 12% 4 500,00\nTotal försäljning 4 500,00'));
      final l = d.lines.single;
      expect(l.categoryId, isNull);
      expect(l.suggestedCategoryId, 1);
      expect(l.warning, isNotNull);
    });

    test('several dates without label are low confidence', () {
      final d = const ZReportParser(_cats)
          .parse(OcrResult.fromPlainText('Z-rapport\n2026-10-28\n2026-10-29 02:00\nTotal försäljning 100,00'));
      expect(d.date.confidence, Confidence.low);
    });

    test('sumWith applies user assignments', () {
      final d = const ZReportParser(_cats).parse(OcrResult.fromPlainText(a4));
      final idx = d.lines.indexWhere((l) => l.label == 'Dryck avhämtning');
      expect(d.sumWith({}), Money.kr(12955 - 70));
      expect(d.sumWith({idx: 3}), Money.kr(12955));
    });
  });
}
