import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:bokforing/domain/z_report_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const _cats = [
  Category(id: 1, name: 'Drycka', vat: VatRate.twelve),
  Category(id: 2, name: 'Mat', vat: VatRate.twelve),
  Category(id: 3, name: 'Mat avhämtning', vat: VatRate.six),
  Category(id: 4, name: 'Tobak', vat: VatRate.twentyFive),
];

ZLine _line(String label) {
  final d = const ZReportParser(_cats).parse(OcrResult.fromPlainText('Z-rapport\nFörsäljning per varugrupp\n$label   49,00\nTotal försäljning   49,00'));
  return d.lines.firstWhere((l) => l.label == label);
}

void main() {
  test('a cut-off name is only suggested, never assigned', () {
    final l = _line('Dryc');
    expect(l.suggestedCategoryId, 1);
    expect(l.categoryId, isNull);
    expect(l.match, MatchKind.possible);
  });

  test('a name with junk around it is only suggested', () {
    expect(_line('XDycka').suggestedCategoryId, 1);
  });

  test('a short or ambiguous name guesses nothing', () {
    expect(_line('Ma').suggestedCategoryId, isNull);
    expect(_line('Mat a').categoryId, isNull);
    expect(_line('Xyz').suggestedCategoryId, isNull);
  });
}
