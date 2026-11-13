import 'package:bokforing/domain/invoice_parser.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/online_parser.dart';
import 'package:bokforing/domain/payslip_parser.dart';
import 'package:bokforing/domain/reading_doubts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a reading that found nothing is doubtful for every document type', () {
    final nothing = OcrResult.fromPlainText('xx');
    expect(invoiceDoubts(const InvoiceParser().parse(nothing)), greaterThan(0));
    expect(onlineDoubts(const OnlineParser().parse(nothing)), greaterThan(0));
    expect(payslipDoubts(const PayslipParser().parse(nothing)), greaterThan(0));
  });

  test('a payslip with its key fields has fewer doubts than an empty reading', () {
    final empty = payslipDoubts(const PayslipParser().parse(OcrResult.fromPlainText('xx')));
    final read = payslipDoubts(const PayslipParser().parse(OcrResult.fromPlainText(
        'Ankan Pub   LÖNEBESKED\nPerson nr. 121212-1212\nAnna Exempel\nUtbetalningsdatum: 2026-10-27\n'
        'Bruttolön   18500,00\nArbetsgivaravgift   5813,00\nPreliminär skatt   4100,00')));
    expect(read, lessThan(empty));
  });
}
