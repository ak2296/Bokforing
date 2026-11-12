import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/dates.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/reports.dart';

/// Builds the monthly table as a PDF, locally. Columns follow the user's
/// categories exactly like the screen. Uses the built-in Helvetica font,
/// which covers Swedish letters.
Future<Uint8List> buildMonthlyPdf(MonthlyReport r, BusinessProfile profile, {DateTime? createdAt}) async {
  final doc = pw.Document(title: 'Månadsrapport ${r.title}', author: profile.name);
  final created = createdAt ?? DateTime.now();
  final manyColumns = r.columns.length > 7;
  final fontSize = manyColumns ? 7.0 : 8.5;
  final cellStyle = pw.TextStyle(fontSize: fontSize);
  final boldStyle = pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold);
  String m(Money v) => v.format(unit: false);

  final headers = ['Datum', for (final c in r.columns) c.name, 'Summa', 'Utgifter', 'Utg. moms', 'Ing. moms'];
  final rows = <List<String>>[
    for (final row in r.exportRows)
      [
        row.hasSalesDifference ? '${row.date} *' : row.date,
        for (final c in r.columns) m(row.amounts[c.key] ?? Money.zero),
        m(row.sales),
        m(row.expenses),
        m(row.outputVat),
        m(row.inputVat),
      ],
  ];
  final totals = [
    'Totalt',
    for (final c in r.columns) m(r.columnTotals[c.key] ?? Money.zero),
    m(r.totalSales),
    m(r.totalExpenses),
    m(r.totalOutputVat),
    m(r.totalInputVat),
  ];

  pw.Widget summaryLine(String label, Money v, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(children: [
          pw.SizedBox(width: 220, child: pw.Text(label, style: bold ? boldStyle : cellStyle)),
          pw.SizedBox(
              width: 90,
              child: pw.Text(v.format(), textAlign: pw.TextAlign.right, style: bold ? boldStyle : cellStyle)),
        ]),
      );

  final diff = r.vatDifference;
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(profile.name.toUpperCase(), style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          if (profile.orgNumber.isNotEmpty) pw.Text('Org.nr ${profile.orgNumber}', style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 2),
          pw.Text(r.title.toUpperCase(), style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 10),
        ],
      ),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Skapad ${SwedishDates.iso(created)} med Quee. Belopp i kronor.',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
          pw.Text('Sida ${context.pageNumber} av ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
        ],
      ),
      build: (context) => [
        pw.TableHelper.fromTextArray(
            headers: headers,
            data: [...rows, totals],
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
            rowDecoration: const pw.BoxDecoration(),
          ),
        pw.SizedBox(height: 14),
        summaryLine('Försäljning i kassan', r.totalSales),
        if (r.onlineCount > 0) summaryLine('Onlineförsäljning (${r.onlineCount} st)', r.totalOnline),
        summaryLine('Total försäljning', r.totalAllSales, bold: true),
        summaryLine('Totala utgifter', r.totalExpenses),
        summaryLine('Total utgående moms (försäljning)', r.totalOutputVat),
        summaryLine('Total ingående moms', r.totalInputVat),
        summaryLine(diff.isNegative ? 'Beräknad moms att få tillbaka' : 'Beräknad moms att betala', diff.abs(),
            bold: true),
        pw.SizedBox(height: 10),
        pw.Text(
          'Beräknad moms utifrån de dokument som registrerats i appen. Detta är inte en momsdeklaration.'
          '${r.onlineCount > 0 ? ' Onlineförsäljning utan moms på pappret är utbetalning efter provision och ingår inte i momsberäkningen.' : ''}'
          '${r.rows.any((x) => x.hasSalesDifference) ? ' * = dagens försäljningsrader stämmer inte med Z-rapportens total.' : ''}',
          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
        ),
      ],
    ),
  );
  return doc.save();
}
