import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:bokforing/domain/z_report_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const _cats = [
  Category(id: 1, name: 'Mat', vat: VatRate.six),
  Category(id: 2, name: 'Vin', vat: VatRate.twentyFive),
  Category(id: 3, name: 'Öl', vat: VatRate.twentyFive),
];

OcrLine _line(String t, double left, double top, double width, {double? angle}) =>
    OcrLine(t, OcrBox(left, top, left + width, top + 20), angle: angle);

OcrResult _ocr(List<OcrLine> lines) =>
    OcrResult(text: lines.map((l) => l.text).join('\n'), blocks: [for (final l in lines) OcrBlock(l.text, l.box, [l])]);

void main() {
  test('tilted photo: label and amount far apart still form one row', () {
    // 3 degrees of tilt: across 800 px the right column sits ~42 px lower.
    const a = 3.0;
    final ocr = _ocr([
      _line('Mat', 50, 100, 60, angle: a),
      _line('1 912,00', 850, 142, 100, angle: a),
      _line('Vin', 50, 130, 60, angle: a),
      _line('89,00', 850, 172, 80, angle: a),
    ]);
    final rows = ocr.rows().map((r) => r.text).toList();
    expect(rows, ['Mat   1 912,00', 'Vin   89,00']);
  });

  test('names and amounts read as separate lines are paired', () {
    final d = const ZReportParser(_cats).parse(OcrResult.fromPlainText(
        'Z-rapport\nFörsäljning per varugrupp\nMat\n1 912,00\nVin\n89,00\nÖl\n5 822,00\nTotal försäljning\n7 823,00'));
    expect(d.lines.map((l) => (l.label, l.amount)).toList(), [
      ('Mat', Money.kr(1912)),
      ('Vin', Money.kr(89)),
      ('Öl', Money.kr(5822)),
    ]);
    expect(d.total.value, Money.kr(7823));
  });

  test('a period row gives the Från date; impossible future dates are dropped', () {
    final d = ZReportParser(_cats, today: DateTime(2026, 10, 31)).parse(OcrResult.fromPlainText(
        'Z-rapport\n2030-10-06\nPeriod 2026-10-30 06:00 - 2026-10-31 05:59\nVarugrupper\nMat 10,00\nTotal försäljning 10,00'));
    expect(d.date.value, '2026-10-30');
    expect(d.otherDates, isNot(contains('2030-10-06')));
  });

  test('page-foot text on the last category row never drops the row', () {
    final d = const ZReportParser(_cats).parse(OcrResult.fromPlainText(
        'Z-rapport\nFörsäljning per varugrupp\nMat   1 912,00\nVin   89,00\n'
        'Öl   2 988,00 kr   https://onsiip360.com#/reports/z-report   1/1\nTotal försäljning   4 989,00'));
    expect(d.lines.map((l) => (l.label, l.amount)).toList(), [
      ('Mat', Money.kr(1912)),
      ('Vin', Money.kr(89)),
      ('Öl', Money.kr(2988)),
    ]);
  });

  test('a short name read with a digit for a letter is suggested, not lost', () {
    final d = const ZReportParser(_cats).parse(OcrResult.fromPlainText(
        'Z-rapport\nFörsäljning per varugrupp\nMat   1 912,00\nVin   89,00\n0l   2 988,00\nTotal försäljning   4 989,00'));
    final line = d.lines.firstWhere((l) => l.amount == Money.kr(2988));
    expect(line.label, '0l');
    expect(line.categoryId, isNull);
    expect(line.suggestedCategoryId, 3);
    expect(line.match, MatchKind.possible);
  });

  test('a nameless amount is guessed from the categories earlier reports used', () {
    const text = 'Z-rapport\nFörsäljning per varugrupp\nMat   100,00\n250,00\nTotal försäljning   350,00';
    final plain = const ZReportParser(_cats).parse(OcrResult.fromPlainText(text));
    expect(plain.lines.firstWhere((l) => l.label == ZLine.unnamed).suggestedCategoryId, 3);
    final learned = const ZReportParser(_cats, usage: {2: 5}).parse(OcrResult.fromPlainText(text));
    expect(learned.lines.firstWhere((l) => l.label == ZLine.unnamed).suggestedCategoryId, 2);
  });

  test('the page tilt is the median line angle, and null without angles', () {
    final tilted = _ocr([
      _line('Mat', 50, 100, 60, angle: 2.0),
      _line('Vin', 50, 130, 60, angle: 3.0),
      _line('Öl', 50, 160, 60, angle: 4.0),
    ]);
    expect(tilted.tiltDegrees, 3.0);
    expect(_ocr([_line('Mat', 50, 100, 60)]).tiltDegrees, isNull);
  });

  test('doubtsOf is zero for a clean reading and counts a nameless row', () {
    final clean = const ZReportParser(_cats).parse(OcrResult.fromPlainText(
        'Z-rapport\nFörsäljning per varugrupp\nMat   1 912,00\nVin   89,00\nTotal försäljning   2 001,00'));
    expect(ZReportParser.doubtsOf(clean), 0);
    final doubtful = const ZReportParser(_cats).parse(OcrResult.fromPlainText(
        'Z-rapport\nFörsäljning per varugrupp\nMat   100,00\n250,00\nTotal försäljning   350,00'));
    expect(ZReportParser.doubtsOf(doubtful), greaterThan(0));
  });
}
