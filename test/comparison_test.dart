import 'dart:convert';

import 'package:bokforing/domain/comparison.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/reports.dart';
import 'package:bokforing/export/table_export.dart';
import 'package:flutter_test/flutter_test.dart';

YearReport _year(int year, int Function(int month) salesKr, {int expensesKr = 0}) => YearReport(year, [
      for (var m = 1; m <= 12; m++) YearRow(m, Money.kr(salesKr(m)), Money.kr(expensesKr), Money.zero, Money.zero),
    ]);

void main() {
  test('each month is set against the same month of the other year', () {
    final a = _year(2026, (m) => m == 9 ? 172300 : 1000);
    final b = _year(2025, (m) => m == 9 ? 158900 : 1000);
    final c = Comparison.of(a, b, CompareMetric.sales);
    expect(c.rows.length, 12);
    expect(c.rows[8].a, Money.kr(172300));
    expect(c.rows[8].b, Money.kr(158900));
    expect(formatChange(c.rows[8].changePercent), '+8 %');
    expect(formatChange(c.rows[0].changePercent), '0 %');
    expect(c.totalA, Money.kr(172300 + 11 * 1000));
  });

  test('a fall shows a minus sign, nothing to compare with shows a dash', () {
    expect(formatChange(const CompareRow(11, Money(18643000), Money(19120000)).changePercent), '−2 %');
    expect(formatChange(CompareRow(1, Money.kr(500), Money.zero).changePercent), '–');
  });

  test('expenses and moms can be compared too', () {
    final a = _year(2026, (m) => 100, expensesKr: 60);
    final b = _year(2025, (m) => 100, expensesKr: 50);
    expect(Comparison.of(a, b, CompareMetric.expenses).rows.first.a, Money.kr(60));
    expect(formatChange(Comparison.of(a, b, CompareMetric.expenses).total.changePercent), '+20 %');
    expect(Comparison.of(a, b, CompareMetric.vat).totalA, Money.zero);
  });

  test('Excel file: semicolons, decimal commas, Swedish letters intact', () {
    final y = _year(2026, (m) => m == 1 ? 1234 : 0);
    final csv = yearTable(y).toCsv();
    expect(csv.take(3), [0xEF, 0xBB, 0xBF]);
    final text = utf8.decode(csv.skip(3).toList());
    final lines = text.split('\r\n');
    expect(lines.first, 'Månad;Försäljning;Varav online;Utgifter;Utgående moms;Ingående moms;Momsskillnad');
    expect(lines[1], startsWith('Januari;1234,00;'));
    expect(lines.last, startsWith('Totalt;1234,00;'));
  });

  test('a comparison table names both years', () {
    final c = Comparison.of(_year(2026, (m) => 10), _year(2025, (m) => 10), CompareMetric.sales);
    final t = comparisonTable(c);
    expect(t.headers, ['Månad', '2026', '2025', 'Skillnad']);
    expect(t.rows.length, 12);
    expect(t.title, 'Försäljning 2026 jämfört med 2025');
  });

  test('a report PDF is made', () async {
    final bytes = await yearTable(_year(2026, (m) => 10)).toPdf(const BusinessProfile(name: 'Test AB'));
    expect(utf8.decode(bytes.take(5).toList()), '%PDF-');
  });
}
