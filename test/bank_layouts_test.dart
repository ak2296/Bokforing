import 'dart:convert';

import 'package:bokforing/domain/bank_statement.dart';
import 'package:flutter_test/flutter_test.dart';

// Invented rows in the column layouts other Swedish banks use. Not real data, and
// the layouts are from memory: they have not been tried on real bank files.
List<int> _csv(String s) => utf8.encode(s);

void main() {
  test('SEB layout: Bokföringsdatum, Text, Belopp, Saldo', () {
    final s = BankStatement.parse(_csv(
        'Bokföringsdatum;Valutadatum;Verifikationsnummer;Text;Belopp;Saldo\n'
        '2026-10-30;2026-10-30;5001;Dryckesgrossisten;-1 250,00;8 750,00\n'
        '2026-10-29;2026-10-29;5000;Swish inbetalning;2 000,00;10 000,00\n'));
    expect(s.rows.length, 2);
    expect(s.rows.first.text, 'Dryckesgrossisten');
    expect(s.rows.first.amount.ore, -125000);
    expect(s.warnings, isEmpty);
  });

  test('Handelsbanken layout: Reskontradatum, Transaktionsdatum, Text, Belopp, Saldo', () {
    final s = BankStatement.parse(_csv(
        'Reskontradatum;Transaktionsdatum;Text;Belopp;Saldo\n'
        '2026-10-30;2026-10-29;Kortköp Willys;-312,50;4 687,50\n'));
    expect(s.rows.single.date, '2026-10-30');
    expect(s.rows.single.text, 'Kortköp Willys');
    expect(s.rows.single.amount.ore, -31250);
  });

  test('Nordea layout: Bokföringsdag, Belopp, Avsändare, Mottagare, Namn, Rubrik, Saldo, Valuta', () {
    final s = BankStatement.parse(_csv(
        'Bokföringsdag;Belopp;Avsändare;Mottagare;Namn;Rubrik;Saldo;Valuta\n'
        '2026/10/30;-800,00;1234 56 78901;BG 123-4567;Hyresvärden AB;Hyra november;4 200,00;SEK\n'));
    final r = s.rows.single;
    expect(r.date, '2026-10-30');
    expect(r.amount.ore, -80000);
    expect(r.text, contains('Hyra november'));
    expect(r.text, contains('Hyresvärden AB'));
  });
}
