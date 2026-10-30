import 'package:bokforing/domain/classifier.dart';
import 'package:bokforing/domain/invoice_extractor.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/patterns.dart';
import 'package:bokforing/domain/validation.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:bokforing/domain/z_extractor.dart';
import 'package:bokforing/samples.dart';
import 'package:flutter_test/flutter_test.dart';

int? p(String s) => Money.parse(s)?.ore;

void main() {
  group('Money parsing och formatering', () {
    test('svenska format', () {
      expect(p('1 250,50'), 125050);
      expect(p('1\u00A0250,50 kr'), 125050);
      expect(p('1250,50'), 125050);
      expect(p('1.250,50'), 125050);
      expect(p('1,250.50'), 125050);
      expect(p('1 250 kr'), 125000);
      expect(p('-50,00'), -5000);
    });
    test('tvetydiga värden avvisas', () {
      expect(p('1.250'), isNull);
      expect(p('1,250'), isNull);
      expect(p('12 50'), isNull);
      expect(p('abc'), isNull);
    });
    test('formatering', () {
      expect(const Money(125050).format(), '1\u00A0250,50\u00A0kr');
      expect(const Money(-100000).format(), '\u22121\u00A0000,00\u00A0kr');
    });
  });

  group('Moms', () {
    test('omvänd beräkning', () {
      expect(VatCalculator.fromGross(Money.kronor(125), VatRate.twentyFive).vat.ore, 2500);
      expect(VatCalculator.fromGross(Money.kronor(112), VatRate.twelve).vat.ore, 1200);
      expect(VatCalculator.fromGross(Money.kronor(106), VatRate.six).vat.ore, 600);
      expect(VatCalculator.fromGross(Money.kronor(125), VatRate.twentyFive).net.ore, 10000);
    });
    test('flera momssatser summerar till 430 kr', () {
      final parts = [250, 120, 60].map((k) => Money.kronor(k)).toList();
      expect(Money.sum(parts), Money.kronor(430));
      expect(AccountingValidationEngine.checkVatBreakdown(parts, Money.kronor(430)).status,
          ValidationStatus.ok);
    });
    test('regler per datum', () {
      expect(VatRuleSet.hintsFor(DateTime(2026, 5, 1)).any((g) => g.rate == VatRate.six), isTrue);
      expect(VatRuleSet.hintsFor(DateTime(2026, 1, 1)).any((g) => g.rate == VatRate.six), isFalse);
    });
  });

  group('Z-rapport', () {
    List<Money> kr(List<int> v) => v.map(Money.kronor).toList();
    test('stämmer', () {
      final r = AccountingValidationEngine.reconcileZReport(
          kr([4500, 300, 800, 2100, 900, 1700, 500]), Money.kronor(10800));
      expect(r.status, ValidationStatus.ok);
    });
    test('skillnad -100 kr', () {
      final r = AccountingValidationEngine.reconcileZReport(
          kr([4500, 300, 800, 2000, 900, 1700, 500]), Money.kronor(10800));
      expect(r.status, ValidationStatus.warning);
      expect(r.difference!.ore, -10000);
    });
    test('extraktion med kategorier och osäker matchning', () {
      final z = extractZReport(sampleZReport, restaurantSuggestions);
      expect(z.date, '2026-10-28');
      expect(z.zNumber, '0142');
      expect(z.total, Money.kronor(10800));
      expect(z.detailedSum, Money.kronor(10800));
      final wine = z.lines.firstWhere((l) => l.label == 'Wine');
      expect(wine.confidence, Confidence.medium);
      expect(wine.categoryId, 'c5');
    });
  });

  group('Klassificering', () {
    test('faktura, kvitto och Z-rapport', () {
      expect(classify(sampleInvoice).type, DocumentType.invoice);
      expect(classify(sampleMultiVat).type, DocumentType.invoice);
      expect(classify(sampleChangeReceipt).type, DocumentType.invoice);
      expect(classify(sampleZReport).type, DocumentType.zReport);
    });
    test('okänt dokument', () {
      expect(classify('Hej! Vi ses på lördag klockan sju.').type, DocumentType.unknown);
    });
  });

  group('Fakturautläsning', () {
    test('summa, moms, datum', () {
      final r = extractInvoice(sampleInvoice);
      expect(r.total, Money.kronor(1250));
      expect(r.totalConfidence, Confidence.high);
      expect(r.vatTotal, Money.kronor(250));
      expect(r.date, '2026-10-27');
      expect(r.dueDate, '2026-11-26');
      expect(r.invoiceNumber, '20261045');
      expect(r.ocrReference, '1234567890');
      expect(r.supplier, 'Nordisk Livs AB');
    });
    test('växel ger inte det största beloppet', () {
      final r = extractInvoice(sampleChangeReceipt);
      expect(r.total, Money.kronor(80));
      expect(r.vatTotal!.ore, 857);
    });
    test('flera momssatser behåller fördelningen', () {
      final r = extractInvoice(sampleMultiVat);
      expect(r.total, Money.kronor(8430));
      expect(r.vatLines.map((v) => v.ratePercent), [25, 12, 6]);
      expect(r.vatTotal, Money.kronor(430));
    });
    test('datum i olika format', () {
      expect(datesIn('28/10/2026'), ['2026-10-28']);
      expect(datesIn('28 okt 2026'), ['2026-10-28']);
    });
  });
}
