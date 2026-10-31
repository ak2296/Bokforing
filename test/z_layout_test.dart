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
}
