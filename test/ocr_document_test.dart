import 'dart:typed_data';

import 'package:bokforing/domain/invoice_extractor.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/ocr_document.dart';
import 'package:bokforing/imaging/preprocess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

OcrLine l(String t, double x0, double y0, double x1, double y1) => OcrLine(t, x0, y0, x1, y1);

void main() {
  group('OcrDocument rader', () {
    test('etikett och belopp på samma rad slås ihop', () {
      final doc = OcrDocument('', [
        l('Totalt', 10, 100, 80, 120),
        l('1 250,00', 300, 103, 380, 123),
        l('Moms 25%', 10, 140, 90, 160),
        l('250,00', 300, 141, 360, 161),
      ]);
      expect(doc.toText(), 'Totalt  1 250,00\nMoms 25%  250,00');
    });

    test('rader sorteras uppifrån och ned oavsett ordning', () {
      final doc = OcrDocument('', [
        l('B', 10, 200, 40, 220),
        l('A', 10, 100, 40, 120),
      ]);
      expect(doc.toText(), 'A\nB');
    });

    test('utläsning fungerar på rekonstruerad text', () {
      final doc = OcrDocument('', [
        l('FAKTURA', 10, 10, 100, 30),
        l('Fakturanummer: 123', 10, 50, 200, 70),
        l('Datum: 2026-10-27', 10, 90, 200, 110),
        l('Att betala', 10, 150, 100, 170),
        l('1 250,00 kr', 300, 151, 400, 171),
      ]);
      final r = extractInvoice(doc.toText());
      expect(r.total, Money.kronor(1250));
      expect(r.date, '2026-10-27');
    });
  });

  group('Bildkvalitet', () {
    test('mörk bild flaggas', () {
      final dark = Uint8List.fromList(img.encodeJpg(img.Image(width: 800, height: 1000)));
      final r = preprocessSync(dark);
      expect(r.issues.any((i) => i.code == 'dark'), isTrue);
    });
  });
}
