import 'package:bokforing/domain/invoice_parser.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Made-up invoice: the due date label is there but its date stands apart.
const _apart = '''
Fakturanummer 813076
Fakturadatum 2026-10-03
Förfallodatum
Betalningsvillkor 30 dagar
Att betala 1 000,00
Bankgiro 123-4567
2026-11-02
''';

void main() {
  test('a due date label with its date apart still gives the due date, marked for checking', () {
    final d = const InvoiceParser().parse(OcrResult.fromPlainText(_apart));
    expect(d.dueDate.value, '2026-11-02');
    expect(d.date.value, '2026-10-03');
  });

  test('a line with a date is never taken as the supplier name', () {
    final d = const InvoiceParser().parse(OcrResult.fromPlainText('Datum: 2026-10-03\nFaktura\nFakturadatum 2026-10-03\nAtt betala 500,00\n'));
    expect(d.supplier.value ?? '', isNot(contains('2026')));
  });
}
