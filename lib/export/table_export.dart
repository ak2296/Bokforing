import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/comparison.dart';
import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/reports.dart';

/// A report as plain rows, used for PDF, print and Excel alike.
class ReportTable {
  final String title;
  final String fileName;
  final List<String> headers;
  final List<List<String>> rows;
  final List<String>? totals;
  const ReportTable({required this.title, required this.fileName, required this.headers, required this.rows, this.totals});

  /// For Excel: semicolons and decimal commas, as Swedish Excel expects, and
  /// a byte order mark so å, ä and ö show correctly.
  Uint8List toCsv() {
    String cell(String s) => s.contains(';') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;
    final lines = [headers, ...rows, ?totals].map((r) => r.map(cell).join(';'));
    return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(lines.join('\r\n'))]);
  }

  Future<Uint8List> toPdf(BusinessProfile profile, {DateTime? createdAt}) async {
    final doc = pw.Document(title: title, author: profile.name);
    final created = createdAt ?? DateTime.now();
    final small = headers.length > 8;
    final cellStyle = pw.TextStyle(fontSize: small ? 7 : 8.5);
    final boldStyle = pw.TextStyle(fontSize: small ? 7 : 8.5, fontWeight: pw.FontWeight.bold);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(profile.name.toUpperCase(), style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          if (profile.orgNumber.isNotEmpty) pw.Text('Org.nr ${profile.orgNumber}', style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 2),
          pw.Text(title.toUpperCase(), style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 10),
        ],
      ),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Skapad ${SwedishDates.iso(created)} med Bokföringsassistent. Belopp i kronor.',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
          pw.Text('Sida ${context.pageNumber} av ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
        ],
      ),
      build: (context) => [
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: [...rows, ?totals],
          headerStyle: boldStyle,
          cellStyle: cellStyle,
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellAlignment: pw.Alignment.centerRight,
          cellAlignments: {0: pw.Alignment.centerLeft},
          border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
            bottom: pw.BorderSide(color: PdfColors.grey600, width: 0.6),
            top: pw.BorderSide(color: PdfColors.grey600, width: 0.6),
          ),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
        ),
      ],
    ));
    return doc.save();
  }
}

/// Kronor with a decimal comma and no spaces, so Excel reads it as a number.
String excelNumber(Money m) => (m.ore / 100).toStringAsFixed(2).replaceAll('.', ',');

ReportTable monthlyTable(MonthlyReport r) {
  String m(Money v) => excelNumber(v);
  return ReportTable(
    title: 'Månadsrapport ${r.title}',
    fileName: 'manadsrapport_${r.year}-${r.month.toString().padLeft(2, '0')}',
    headers: ['Datum', for (final c in r.columns) c.name, 'Summa', 'Utgifter', 'Utgående moms', 'Ingående moms'],
    rows: [
      for (final row in r.rows)
        [
          row.date,
          for (final c in r.columns) m(row.amounts[c.key] ?? Money.zero),
          m(row.sales),
          m(row.expenses),
          m(row.outputVat),
          m(row.inputVat),
        ],
      if (r.onlineCount > 0) ['Onlineförsäljning', for (final _ in r.columns) '', m(r.totalOnline), '', m(r.onlineVat), ''],
    ],
    totals: [
      'Totalt',
      for (final c in r.columns) m(r.columnTotals[c.key] ?? Money.zero),
      m(r.totalAllSales),
      m(r.totalExpenses),
      m(r.totalOutputVat),
      m(r.totalInputVat),
    ],
  );
}

ReportTable yearTable(YearReport y) {
  String m(Money v) => excelNumber(v);
  return ReportTable(
    title: 'Årsöversikt ${y.year}',
    fileName: 'arsoversikt_${y.year}',
    headers: const ['Månad', 'Försäljning', 'Varav online', 'Utgifter', 'Utgående moms', 'Ingående moms', 'Momsskillnad'],
    rows: [
      for (final r in y.rows)
        [r.monthName, m(r.sales), m(r.online), m(r.expenses), m(r.outputVat), m(r.inputVat), m(r.vatDifference)],
    ],
    totals: ['Totalt', m(y.sales), m(y.online), m(y.expenses), m(y.outputVat), m(y.inputVat), m(y.vatDifference)],
  );
}

ReportTable comparisonTable(Comparison c) {
  String m(Money v) => excelNumber(v);
  final name = c.metric.label.toLowerCase();
  return ReportTable(
    title: '${c.metric.label} ${c.yearA} jämfört med ${c.yearB}',
    fileName: 'jamforelse_${name.replaceAll(' ', '_')}_${c.yearA}_${c.yearB}',
    headers: ['Månad', '${c.yearA}', '${c.yearB}', 'Skillnad'],
    rows: [
      for (final r in c.rows)
        [SwedishDates.capitalize(SwedishDates.months[r.month - 1]), m(r.a), m(r.b), formatChange(r.changePercent)],
    ],
    totals: ['Totalt', m(c.totalA), m(c.totalB), formatChange(c.total.changePercent)],
  );
}
