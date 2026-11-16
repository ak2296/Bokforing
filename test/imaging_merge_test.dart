import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/text_merge.dart';
import 'package:bokforing/imaging/preprocess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A synthetic photo: dark table, white paper, dark text lines.
img.Image _photo({int brightness = 255, bool blurred = false}) {
  final im = img.Image(width: 800, height: 1000);
  img.fill(im, color: img.ColorRgb8(40, 40, 40));
  img.fillRect(im, x1: 150, y1: 120, x2: 650, y2: 900, color: img.ColorRgb8(brightness, brightness, brightness));
  for (var y = 180; y < 860; y += 40) {
    for (var x = 190; x < 610; x += 14) {
      img.fillRect(im, x1: x, y1: y, x2: x + 8, y2: y + 14, color: img.ColorRgb8(20, 20, 20));
    }
  }
  return blurred ? img.gaussianBlur(im, radius: 12) : im;
}

void main() {
  group('Preprocess', () {
    test('finds and crops the paper, good quality passes', () {
      final r = preprocessDocument(PreprocessRequest(img.encodeJpg(_photo())));
      expect(r.quality.paperFound, isTrue);
      expect(r.width, lessThan(800));
      expect(r.height, lessThan(1000));
      expect(r.quality.issues, isEmpty);
      expect(r.quality.skewDegrees.abs(), lessThan(1));
    });

    test('a narrow strip (thermal paper) is enlarged so its small print has pixels to read', () {
      final im = img.Image(width: 700, height: 2600);
      img.fill(im, color: img.ColorRgb8(40, 40, 40));
      img.fillRect(im, x1: 250, y1: 100, x2: 450, y2: 2500, color: img.ColorRgb8(255, 255, 255));
      for (var y = 160; y < 2440; y += 40) {
        for (var x = 270; x < 430; x += 10) {
          img.fillRect(im, x1: x, y1: y, x2: x + 5, y2: y + 12, color: img.ColorRgb8(20, 20, 20));
        }
      }
      // The user's frame cuts the strip out of the photo.
      final r = preprocessDocument(PreprocessRequest(img.encodeJpg(im), frame: [250 / 700, 100 / 2600, 450 / 700, 2500 / 2600]));
      expect(r.width, greaterThan(330)); // the strip itself is about 200 px wide
      expect(r.height, greaterThan(r.width * 5));
    });

    test('dark photo is reported', () {
      final dark = img.adjustColor(_photo(), brightness: 0.25);
      final r = preprocessDocument(PreprocessRequest(img.encodeJpg(dark)));
      expect(r.quality.issues, contains(QualityIssue.tooDark));
    });

    test('blurry photo is reported', () {
      final r = preprocessDocument(PreprocessRequest(img.encodeJpg(_photo(blurred: true))));
      expect(r.quality.issues, contains(QualityIssue.blurry));
    });

    test('tilted document is straightened', () {
      final tilted = img.copyRotate(_photo(), angle: 5);
      final r = preprocessDocument(PreprocessRequest(img.encodeJpg(tilted)));
      expect(r.quality.skewDegrees.abs(), greaterThan(3));
      expect(r.quality.skewDegrees.abs(), lessThan(7));
    });
  });

  group('TextMerge', () {
    test('overlapping rows from two photos appear once', () {
      final a = OcrResult.fromPlainText('Z-rapport\nMat 1 912,00\nÖl 5 822,00');
      final b = OcrResult.fromPlainText('Öl 5 822,00\nVin 89,00\nTotal försäljning 7 823,00');
      final merged = TextMerge.merge([a, b]).rows().map((r) => r.text).toList();
      expect(merged, ['Z-rapport', 'Mat 1 912,00', 'Öl 5 822,00', 'Vin 89,00', 'Total försäljning 7 823,00']);
    });
  });
}
