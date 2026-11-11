import 'package:bokforing/domain/classifier.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/payslip_parser.dart';
import 'package:bokforing/domain/text_patterns.dart';
import 'package:flutter_test/flutter_test.dart';

// Made-up payslip text in the layout of a payroll system whose headings sit on
// one row and the values on the next (the camera text keeps them three spaces
// apart). Names, numbers and pay are invented, with a few typical camera
// mistakes: no ö in some words, the year of the period end misread.
const _columns = '''
Ankan Pub & Pizzeria   LÖNEBESKED
Anstallningsnummer: 7   Person nr.
121212-1212
Loneperiod:   2026-10-01   till
2016-10-31   Anna Exempel
Utbetalningsdatum:   2026-10-27
Bankkontonummer:   Malmo
Sverige
Löneart   Benamning   Datuminfo   Antal
Enhet   A-pris   Belopp
Lön   Oktober   18500   18500,00
Betald sem. dgr   Ack. Bruttolon
Preliminär skatt   Skattegrundande lon
Bruttolon)
0   0,00   31,00%   18500,00   18500,00
Obetald sem. dgr   Ack. Preliminarskat
Arbetsgivaravgift   Kostnadsavdrag
25   0.00   5813,00   0,00
Sparad sem. dgr   Ack. Förmåner
Arbetsgivaravgift   Förmån   Preliminär
skatt
0,00   31,42%   0,00   4100,00
Netto +l-
Semesteravsattning   Ack. Semestergr lön
Semesteron   Semestergr. lön
0,00   0,00   12,00%   0,00   0,00
Nettoion
Arbetad tid   Övertid   Frånvaro   Flextid
14400,00
0.00   0,00   0.00   0.00)
Adress   Telefon   Fax
Organisationsnummer
Provvägen 12   040-111111   040-111111
556000_0000
12345 Malmo
''';

const _simple = '''
Lönespecifikation
Bruttolön   18 500,00
Arbetsgivaravgift   5 813,00
Preliminär skatt   4 100,00
Nettolön   14 400,00
Utbetalningsdag   2026-10-27
Löneperiod   2026-10-01   2026-10-31
''';

PayslipDraft _read(String text) => const PayslipParser().parse(OcrResult.fromPlainText(text));

void main() {
  group('classifier', () {
    const c = DocumentClassifier();

    test('a lönebesked is a payslip, also with the accents lost', () {
      final r = c.classify(_columns);
      expect(r.type, DocumentType.payslip);
      expect(r.isCertain, isTrue);
      expect(c.classify(_simple).type, DocumentType.payslip);
    });

    test('an invoice that mentions arbetsgivaravgift stays an invoice', () {
      final r = c.classify('Faktura   Fakturanummer 1001\nFörfallodatum 2026-11-30\nAtt betala 1 250,00\n'
          'Bankgiro 123-4567   OCR 1234567890\nInkluderar arbetsgivaravgift');
      expect(r.type, DocumentType.invoice);
    });

    test('a payout paper with Utbetalningsdatum is not a payslip', () {
      final r = c.classify('Betalningsbekräftelse   Utbetalningsdatum 2026-10-27\nBetalt belopp 2 000,00\nFoodora');
      expect(r.type, isNot(DocumentType.payslip));
    });
  });

  group('reading the column layout', () {
    final d = _read(_columns);

    test('bruttolön, arbetsgivaravgift and preliminär skatt', () {
      expect(d.gross.value, Money.parse('18500,00'));
      expect(d.employerFee.value, Money.parse('5813,00'));
      expect(d.tax.value, Money.parse('4100,00'));
      expect(d.net.value, Money.parse('14400,00'));
      expect(d.feeRate, closeTo(31.42, 0.001));
    });

    test('the sums on the paper make the amounts sure', () {
      expect(d.gross.confidence, Confidence.high);
      expect(d.tax.confidence, Confidence.high);
      expect(d.employerFee.confidence, Confidence.high);
    });

    test('the date is the payout date, and the period is kept', () {
      expect(d.payoutDate.value, '2026-10-27');
      expect(d.periodFrom.value, '2026-10-01');
    });

    test('a period end before the start is unsure and a correction is offered, not applied', () {
      expect(d.periodTo.value, '2016-10-31');
      expect(d.periodTo.confidence, Confidence.low);
      expect(d.periodToSuggestion, '2026-10-31');
    });

    test('the employee, not the company', () {
      expect(d.personnummer.value, '121212-1212');
      expect(d.employeeName.value, 'Anna Exempel');
    });
  });

  group('reading labels with their amounts', () {
    final d = _read(_simple);

    test('amounts', () {
      expect(d.gross.value, Money.parse('18500,00'));
      expect(d.employerFee.value, Money.parse('5813,00'));
      expect(d.tax.value, Money.parse('4100,00'));
      expect(d.gross.confidence, Confidence.high);
    });

    test('dates, with a sane period', () {
      expect(d.payoutDate.value, '2026-10-27');
      expect(d.periodFrom.value, '2026-10-01');
      expect(d.periodTo.value, '2026-10-31');
      expect(d.periodToSuggestion, isNull);
    });

    test('missing name is reported, not invented', () {
      expect(d.employeeName.hasValue, isFalse);
      expect(d.notes.any((n) => n.contains('Namnet')), isTrue);
    });
  });

  test('when bruttolön minus skatt is not the nettolön the reader says so', () {
    final d = _read(_simple.replaceAll('14 400,00', '14 000,00'));
    expect(d.gross.confidence, Confidence.medium);
    expect(d.notes.any((n) => n.contains('nettolönen')), isTrue);
  });

  test('a missing arbetsgivaravgift is calculated from the printed rate, marked to check', () {
    final d = _read('Lönebesked\nBruttolön   10 000,00\nArbetsgivaravgift   31,42 %\nPreliminär skatt   2 000,00\n'
        'Nettolön   8 000,00');
    expect(d.employerFee.value, Money.parse('3142,00'));
    expect(d.employerFee.confidence, Confidence.medium);
  });
}
