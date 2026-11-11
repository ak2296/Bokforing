import 'dart:convert';

import 'package:bokforing/domain/bank_matcher.dart';
import 'package:bokforing/domain/bank_statement.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:flutter_test/flutter_test.dart';

// Made-up bank files. Never paste a real bank file here.

/// A bank export the way Swedish banks write it: Windows-1252 text (the title
/// line has a raw 0x96 dash, which is not valid UTF-8), a `*` title line, then
/// the header and the rows, newest first.
List<int> _bankFile({int balance2 = 500000}) => [
      ...latin1.encode('* Transaktioner Period 2026-10-01'),
      0x96,
      ...latin1.encode('2026-10-31 Skapad 2026-11-01 10:00 CET\r\n'),
      ...latin1.encode(
          'Radnummer,Clearingnummer,Kontonummer,Produkt,Valuta,Bokföringsdag,Transaktionsdag,Valutadag,Referens,Beskrivning,Belopp,Bokfört saldo\r\n'
          '1,10000,1000000001,"Företagskonto",SEK,2026-10-20,2026-10-20,2026-10-20,"GROSSISTEN AB","GROSSISTEN AB",-521.00,4479.00\r\n'
          '2,10000,1000000001,"Företagskonto",SEK,2026-10-18,2026-10-18,2026-10-18,"Hyra, lokal","Hyra, lokal",-8000.00,${(balance2 / 100).toStringAsFixed(2)}\r\n'
          '3,10000,1000000001,"Företagskonto",SEK,2026-10-15,2026-10-15,2026-10-15,"","Överföring",13000.00,13000.00\r\n'),
    ];

Invoice _inv(int id, String supplier, int total, String date, {String number = '', String ocr = ''}) => Invoice(
      id: id,
      invoiceDate: date,
      supplier: supplier,
      invoiceNumber: number,
      ocrReference: ocr,
      total: Money(total),
      vatTotal: Money.zero,
      meta: const RecordMeta(source: RecordSource.manual),
    );

BankRow _row(String date, int amount, String text) => BankRow(date: date, text: text, amount: Money(amount));

void main() {
  group('reading a bank file', () {
    test('Windows-1252, a title line, quoted commas and newest-first rows', () {
      final s = BankStatement.parse(_bankFile());
      expect(s.rows.length, 3);
      expect(s.warnings, isEmpty);
      expect(s.rows[0].date, '2026-10-20');
      expect(s.rows[0].amount, const Money(-52100));
      expect(s.rows[0].text, 'GROSSISTEN AB'); // reference and description are the same: said once
      expect(s.rows[0].balance, const Money(447900));
      expect(s.rows[1].text, 'Hyra, lokal'); // the comma stays inside the text
      expect(s.rows[2].text, 'Överföring'); // the Ö is read right
      expect(s.rows[2].amount, const Money(1300000));
    });

    test('semicolons, a BOM, Swedish amounts and the saldo column under another name', () {
      final bytes = utf8.encode('﻿Datum;Text;Belopp;Saldo\n'
          '2026-10-02;"Kaffe; bönor";-1 250,50;100,00\n'
          '2026-10-01;Insättning;1 350,50;1 350,50\n');
      final s = BankStatement.parse(bytes);
      expect(s.rows.length, 2);
      expect(s.rows[0].amount, const Money(-125050));
      expect(s.rows[0].text, 'Kaffe; bönor');
      expect(s.warnings, isEmpty);
    });

    test('a saldo that does not follow from the rows gives a warning, not an error', () {
      final s = BankStatement.parse(_bankFile(balance2: 999900));
      expect(s.rows.length, 3);
      expect(s.warnings.single, contains('Saldot'));
    });

    test('a row that cannot be read is skipped and counted', () {
      final bytes = utf8.encode('Datum,Text,Belopp\n2026-10-02,Kaffe,-10.00\nimorgon,Fel,5.00\n');
      final s = BankStatement.parse(bytes);
      expect(s.rows.length, 1);
      expect(s.warnings.single, contains('1 rad'));
    });

    test('a file that is not a bank CSV is refused with a message', () {
      expect(() => BankStatement.parse(utf8.encode('Namn;Text\nA;B\n')), throwsFormatException);
      expect(() => BankStatement.parse(utf8.encode('Datum;Text;Belopp\n')), throwsFormatException);
      expect(() => BankStatement.parse(utf8.encode('Text;Belopp\nA;5,00\n')), throwsFormatException);
    });
  });

  group('matching payments with unpaid invoices', () {
    test('the exact amount pairs them; a name in the text makes it sure', () {
      final rows = BankStatement.parse(_bankFile()).rows;
      final unpaid = [
        _inv(1, 'Grossisten AB', 52100, '2026-10-10'),
        _inv(2, 'Fastighets AB Hyran', 800000, '2026-10-01'),
      ];
      final r = BankMatcher.match(rows, unpaid);
      expect(r.matches.length, 2);
      final gross = r.matches.firstWhere((m) => m.invoice.id == 1);
      final rent = r.matches.firstWhere((m) => m.invoice.id == 2);
      expect(gross.sure, isTrue);
      expect(gross.row.date, '2026-10-20');
      expect(rent.sure, isFalse); // right amount, but no name or number in the text
      expect(r.unmatchedOut, isEmpty);
      expect(r.unmatchedIn, 1);
    });

    test('an invoice or OCR number in the text is as good as a name', () {
      final r = BankMatcher.match(
          [_row('2026-10-20', -52100, 'Bg 5555-1234 OCR 7700123456')], [_inv(1, 'Okänt', 52100, '2026-10-10', ocr: '7700123456')]);
      expect(r.matches.single.sure, isTrue);
    });

    test('two invoices with the same amount: the named one is chosen, but it is not sure', () {
      final r = BankMatcher.match([
        _row('2026-10-20', -10000, 'BETA STOCKHOLM')
      ], [
        _inv(3, 'Alfa AB', 10000, '2026-10-01'),
        _inv(4, 'Beta AB', 10000, '2026-10-01'),
      ]);
      expect(r.matches.single.invoice.id, 4);
      expect(r.matches.single.sure, isFalse);
    });

    test('a credit note is a payment in', () {
      final r = BankMatcher.match([_row('2026-10-20', 10000, 'ALFA KREDIT')], [_inv(5, 'Alfa Kredit', -10000, '2026-10-01')]);
      expect(r.matches.single.invoice.id, 5);
      expect(r.unmatchedIn, 0);
    });

    test('a payment a long time before the invoice date is not a payment of it', () {
      final r = BankMatcher.match([_row('2026-10-01', -10000, 'ALFA')], [_inv(6, 'Alfa AB', 10000, '2026-10-20')]);
      expect(r.matches, isEmpty);
      expect(r.unmatchedOut.length, 1);
    });

    test('each payment and each invoice is used once', () {
      final r = BankMatcher.match([
        _row('2026-10-20', -10000, 'ALFA'),
        _row('2026-10-21', -10000, 'ALFA'),
      ], [
        _inv(7, 'Alfa AB', 10000, '2026-10-01'),
      ]);
      expect(r.matches.length, 1);
      expect(r.unmatchedOut.length, 1);
    });

    test('payments that pay no invoice are listed', () {
      final r = BankMatcher.match([_row('2026-10-20', -12345, 'NÅGOT ANNAT')], [_inv(8, 'Alfa AB', 10000, '2026-10-01')]);
      expect(r.matches, isEmpty);
      expect(r.unmatchedOut.single.text, 'NÅGOT ANNAT');
    });
  });
}
