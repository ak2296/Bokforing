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
      expect(wine.categoryId, '');
      expect(wine.suggestedId, 'c5');
      expect(z.detailedSum, Money.kronor(9100));
      expect(z.sumWith({z.lines.indexOf(wine): 'c5'}), Money.kronor(10800));
    });
  });

  group('Z-rapport med sektioner', () {
    const a4 = '''Z-RAPPORT
Datum 2026-10-31
Periodens försäljning kr 12 955,00
Öresutjämning kr 0,00
Betalningar kr 619,00
Tjänster x kr 0,00
Varor x kr 12 955,00
Försäljning per varugrupp exkl returer
Dryck kr 163,00
Dryck avhämtning kr 70,00
Mat kr 1 912,00
Mat avhämtning kr 1 507,00
Sprit kr 880,00
Tobak kr 2 512,00
Vin kr 89,00
Öl kr 5 822,00
Försäljning per momsgrupp exkl returer
Moms 12% 1 000,00
Kassalåda och växelkassa
Ingående växelkassa 500,00 kr''';
    test('bara varugruppssektionen används och totalen hittas', () {
      final z = extractZReport(a4, restaurantSuggestions);
      expect(z.sectionFound, isTrue);
      expect(z.total, Money.kronor(12955));
      expect(z.date, '2026-10-31');
      expect(z.lines.length, 8);
      expect(Money.sum(z.lines.map((l) => l.amount)), Money.kronor(12955));
    });
    test('Mat avhämtning tilldelas aldrig automatiskt till Mat', () {
      final z = extractZReport(a4, restaurantSuggestions);
      final mat = z.lines.firstWhere((l) => l.label == 'Mat avhämtning');
      expect(mat.categoryId, '');
      expect(mat.suggestedId, 'c0');
      expect(z.lines.firstWhere((l) => l.label == 'Mat').categoryId, 'c0');
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

  group('Riktiga dokument', () {
    const centrum = '''CENTRUMGROSSISTEN AB
FAKTURA
Fakturanr 138956
Kundnr 999
2026-10-30
Förfallodatum Leveranstid Ordernr
2026-10-30 20261030 60719
Momspliktigt belopp 491,87
Moms 6% 29,47
Moms 25% 0,00
Öresutj. -0,34
Att betala SEK 521,00''';
    const willys = '''WILLYS
Katrinelund Malmö
Totalt 29 varor
Totalt 598,90 SEK
Mottaget Kontokort 598,90
DEBIT MASTERCARD
KÖP 598.9 SEK
Ref: 200229765603
2026-10-28 16:43:42
Moms% Moms Netto Brutto
6,00 31,05 517,95 549,00
25,00 9,98 39,92 49,90
SPARA KVITTOT''';
    const lunds = '''Lunds Universitet
Box 117
221 00 Lund
Datum: 28 okt. 2026 14:19
Nummer: YB1L-218
1x200,00kr 200,00kr
Totalt
200,00kr
Kortbetalning.
Kvittot finns tillgängligt på
receipt.elementarypos.com''';

    test('faktura med momspliktigt belopp och öresavrundning', () {
      expect(classify(centrum).type, DocumentType.invoice);
      final r = extractInvoice(centrum);
      expect(r.total, Money.kronor(521));
      expect(r.net!.ore, 49187);
      expect(r.vatTotal!.ore, 2947);
      expect(r.vatLines.map((v) => v.ratePercent), [6, 25]);
      expect(r.vatConfidence, Confidence.high);
    });
    test('kvitto med momstabell', () {
      expect(classify(willys).type, DocumentType.invoice);
      final r = extractInvoice(willys);
      expect(r.total!.ore, 59890);
      expect(r.vatLines.map((v) => v.vat.ore), [3105, 998]);
      expect(r.vatLines.map((v) => v.net!.ore), [51795, 3992]);
      expect(r.vatTotal!.ore, 4103);
      expect(r.vatConfidence, Confidence.high);
    });
    test('Centrumgrossisten: leverantör och förfallodatum', () {
      const t = '''FAKTURA
Fakturanr 138956
Kundnr 999 1
CENTRUMGROSSISTEN AB
Förfallodatum Leveranstid Ordernr
2026-10-30 20261030 60719
Att betala SEK 521,00''';
      final r = extractInvoice(t);
      expect(r.supplier, 'CENTRUMGROSSISTEN AB');
      expect(r.dueDate, '2026-10-30');
    });
    test('kortkvitto utan moms känns igen som utgift', () {
      expect(classify(lunds).type, DocumentType.invoice);
      final r = extractInvoice(lunds);
      expect(r.total, Money.kronor(200));
      expect(r.date, '2026-10-28');
      expect(r.vatTotal, isNull);
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
      expect(r.total, Money.kronor(3430));
      expect(r.vatLines.map((v) => v.ratePercent), [25, 12, 6]);
      expect(r.vatLines.map((v) => v.net), everyElement(Money.kronor(1000)));
      expect(r.vatTotal, Money.kronor(430));
      for (final l in r.vatLines) {
        expect(AccountingValidationEngine.checkVatLine(l.ratePercent, l.net!, l.vat).status,
            ValidationStatus.ok);
      }
      expect(r.candidates.where((c) => c.value != r.total), isEmpty);
    });
    test('moms som inte stämmer med underlaget varnar', () {
      expect(AccountingValidationEngine.checkVatLine(25, Money.kronor(1000), Money.kronor(2000)).status,
          ValidationStatus.warning);
    });
    test('datum i olika format', () {
      expect(datesIn('28/10/2026'), ['2026-10-28']);
      expect(datesIn('28 okt 2026'), ['2026-10-28']);
    });
  });
}
