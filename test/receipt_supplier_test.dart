import 'package:bokforing/domain/invoice_parser.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Made-up receipt text. At the top the shop's logo was read as a bracket and a
// stray letter in front of the name, as the camera text does with a round logo.
const _logoBracket = '''
(C Shopnamn
Storgatan 1
232 37 ARLÖV
KVITTO   DATUM
2073542   20261114 14:49
LAMPA 3 x 199,90   599.70
Totalt   1,389.00 kr
MOMS   25.0%   277.80
Kontokort   1,389.00
''';

void main() {
  test('a logo read as a bracket and a stray letter is not part of the supplier name', () {
    final d = const InvoiceParser().parse(OcrResult.fromPlainText(_logoBracket));
    expect(d.supplier.value, isNotNull);
    expect(d.supplier.value, isNot(startsWith('(')));
    expect(d.supplier.value, 'Shopnamn');
  });
}
