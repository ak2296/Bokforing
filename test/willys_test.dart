import 'package:bokforing/domain/invoice_parser.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/text_patterns.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Willys as the phone read it: item count ignored, split decimal repaired', () {
    final d = const InvoiceParser().parse(OcrResult.fromPlainText('''
WiLLY:S
Totalt 29 varor
Totalt   598, 90 SEK
Mottaget Kontokort 598,90
Moms% Moms Netto Brutto
6,00 31,05 517,95 549,00
25,00 9,98 39,92 49,90
2026-10-28 14:32'''));
    expect(d.total.value, const Money(59890));
    expect(d.total.confidence, Confidence.high);
    expect(d.totalCandidates.map((c) => c.value), isNot(contains(Money.kr(29))));
    expect(d.vatTotal.value, const Money(4103));
    expect(d.date.value, '2026-10-28');
    expect(d.date.confidence, Confidence.high);
  });

  test('OCR clean-up joins "598, 90" and "598 ,90" but leaves lists alone', () {
    expect(OcrResult.cleanOcrText('Totalt 598, 90 SEK'), 'Totalt 598,90 SEK');
    expect(OcrResult.cleanOcrText('Totalt 598 ,90'), 'Totalt 598,90');
    expect(OcrResult.cleanOcrText('6,00 31,05 517,95 549,00'), '6,00 31,05 517,95 549,00');
  });
}
