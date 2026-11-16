import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/comparison.dart';
import '../domain/balances.dart';
import '../domain/dates.dart';
import '../domain/ledger.dart';
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
    addTo(doc, profile, createdAt ?? DateTime.now());
    return doc.save();
  }

  /// How many A4 pages the report takes on paper.
  Future<int> pageCount(BusinessProfile profile) async {
    final doc = pw.Document();
    addTo(doc, profile, DateTime.now());
    await doc.save();
    return doc.document.pdfPageList.pages.length;
  }

  /// Adds the report to [doc] as pages, so several reports can be one PDF.
  void addTo(pw.Document doc, BusinessProfile profile, DateTime created) {
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
          pw.Text('Skapad ${SwedishDates.iso(created)} med Quee. Belopp i kronor.',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
          pw.Text('Sida ${context.pageNumber} av ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
        ],
      ),
      build: (context) => [
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: [...rows, ?totals],
          headerStyle: boldStyle.copyWith(color: const PdfColor.fromInt(0xFF0B6B4E)),
          cellStyle: cellStyle,
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEAF4EF)),
          oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF6F8F6)),
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
      for (final row in r.exportRows)
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

/// Verifikationslistan: every verification with its lines, in date order
/// (the registreringsordning of the bokföring). Numbers are the series
/// letter and number the SIE file gives them.
ReportTable voucherListTable(Ledger l, String period) {
  String m(Money v) => excelNumber(v);
  final rows = <List<String>>[];
  for (final v in l.vouchers) {
    var first = true;
    for (final r in v.lines) {
      rows.add([
        first ? '${v.series}${v.number}' : '',
        first ? v.date : '',
        first ? v.text : '',
        '${r.account}',
        r.name,
        r.debit.isZero ? '' : m(r.debit),
        r.credit.isZero ? '' : m(r.credit),
      ]);
      first = false;
    }
  }
  return ReportTable(
    title: 'Verifikationslista $period',
    fileName: 'verifikationslista_${period.replaceAll(' ', '_')}',
    headers: const ['Ver.nr', 'Datum', 'Text', 'Konto', 'Kontonamn', 'Debet', 'Kredit'],
    rows: rows,
    totals: ['Totalt', '', '', '', '', m(l.totalDebit), m(l.totalCredit)],
  );
}

/// Huvudboken: each account with its transactions and a running balance
/// (the systematic order of the bokföring).
ReportTable generalLedgerTable(Ledger l, String period) {
  String m(Money v) => excelNumber(v);
  final rows = <List<String>>[];
  for (final a in l.accounts) {
    rows.add(['Konto ${a.number} ${a.name}', '', '', '', '', '']);
    var running = Money.zero;
    for (final x in a.lines) {
      running = running + x.debit - x.credit;
      rows.add([x.date, x.ver, x.text, x.debit.isZero ? '' : m(x.debit), x.credit.isZero ? '' : m(x.credit), m(running)]);
    }
    rows.add(['Summa ${a.number}', '', '', m(a.debit), m(a.credit), m(a.balance)]);
  }
  return ReportTable(
    title: 'Huvudbok $period',
    fileName: 'huvudbok_${period.replaceAll(' ', '_')}',
    headers: const ['Datum', 'Ver.nr', 'Text', 'Debet', 'Kredit', 'Saldo'],
    rows: rows,
    totals: ['Totalt', '', '', m(l.totalDebit), m(l.totalCredit), m(l.totalDebit - l.totalCredit)],
  );
}

/// Saldobalansen: the sums of every account for the period. Without opening
/// balances: only what is registered in the app.
ReportTable trialBalanceTable(Ledger l, String period) {
  String m(Money v) => excelNumber(v);
  return ReportTable(
    title: 'Saldobalans $period',
    fileName: 'saldobalans_${period.replaceAll(' ', '_')}',
    headers: const ['Konto', 'Kontonamn', 'Debet', 'Kredit', 'Saldo'],
    rows: [for (final a in l.accounts) ['${a.number}', a.name, m(a.debit), m(a.credit), m(a.balance)]],
    totals: [
      'Totalt',
      l.balances ? 'Debet och kredit stämmer' : 'Debet och kredit stämmer INTE',
      m(l.totalDebit),
      m(l.totalCredit),
      m(l.totalDebit - l.totalCredit),
    ],
  );
}

/// Resultaträkning on the BAS accounts: sales (3xxx) and costs (4xxx to 7xxx).
ReportTable incomeStatementTable(Ledger l, String period) {
  String m(Money v) => excelNumber(v);
  return ReportTable(
    title: 'Resultaträkning $period',
    fileName: 'resultatrakning_${period.replaceAll(' ', '_')}',
    headers: const ['Konto', 'Kontonamn', 'Belopp'],
    rows: [
      ['', 'Rörelsens intäkter', ''],
      for (final a in l.incomeAccounts) ['${a.number}', a.name, m(-a.balance)],
      ['', 'Summa intäkter', m(l.income)],
      ['', 'Rörelsens kostnader', ''],
      for (final a in l.costAccounts) ['${a.number}', a.name, m(-a.balance)],
      ['', 'Summa kostnader', m(-l.costs)],
    ],
    totals: ['', 'Resultat', m(l.result)],
  );
}

/// Balansräkning (utkast): assets on top, equity and debts below. Built from
/// the opening balances the owner entered and the verifications of the period.
ReportTable balanceSheetTable(BalanceSheet s) {
  String m(Money v) => excelNumber(v);
  return ReportTable(
    title: 'Balansräkning ${s.asOf} (utkast)',
    fileName: 'balansrakning_${s.asOf}',
    headers: const ['Post', 'Belopp'],
    rows: [
      ['TILLGÅNGAR', ''],
      for (final r in s.assetRows) [r.label, m(r.amount)],
      ['Summa tillgångar', m(s.totalAssets)],
      ['EGET KAPITAL OCH SKULDER', ''],
      for (final r in s.equityDebtRows) [r.label, m(r.amount)],
    ],
    totals: ['Summa eget kapital och skulder', m(s.totalEquityDebts)],
  );
}

/// The straight-line write-off plan of every asset the owner entered.
ReportTable depreciationTable(OpeningBalances o) {
  String m(Money v) => excelNumber(v);
  final start = (SwedishDates.parseIso(o.date) ?? DateTime.now()).year;
  return ReportTable(
    title: 'Avskrivningsplan (utkast)',
    fileName: 'avskrivningsplan',
    headers: const ['Tillgång', 'År', 'Avskrivning', 'Värde vid årets slut'],
    rows: [
      for (final e in o.entries)
        for (final y in depreciationPlan(e, start)) [e.name.isEmpty ? e.kind.label : e.name, '${y.year}', m(y.amount), m(y.valueAtEnd)],
    ],
  );
}

/// The first month of every loan the owner entered.
ReportTable loanTable(OpeningBalances o) {
  String m(Money v) => excelNumber(v);
  return ReportTable(
    title: 'Lånplan (utkast)',
    fileName: 'lanplan',
    headers: const ['Lån', 'Kvar', 'Ränta per år', 'Månader kvar', 'Amortering per månad', 'Ränta första månaden'],
    rows: [
      for (final e in o.entries)
        if (loanFirstMonth(e) != null)
          [
            e.name.isEmpty ? e.kind.label : e.name,
            m(e.amount),
            '${e.ratePercent ?? 0} %',
            '${e.monthsLeft}',
            m(loanFirstMonth(e)!.amortisation),
            m(loanFirstMonth(e)!.interest),
          ],
    ],
  );
}

/// Support for the momsdeklaration: the boxes of Skatteverket's form, built from
/// the SIE accounts (3001-3003 sales, 2611-2631 output VAT, 2641 input VAT).
/// An estimate from what is registered, not a declaration.
ReportTable vatBasisTable(Ledger l, String period) {
  String m(Money v) => excelNumber(v);
  Money sales(int a) => -l.balanceOf(a);
  final base = [sales(3001), sales(3002), sales(3003)];
  final out = [sales(2611), sales(2621), sales(2631)];
  final input = l.balanceOf(2641);
  final outTotal = Money.sum(out);
  return ReportTable(
    title: 'Momsunderlag $period',
    fileName: 'momsunderlag_${period.replaceAll(' ', '_')}',
    headers: const ['Ruta', 'Beskrivning', '25 %', '12 %', '6 %', 'Summa'],
    rows: [
      ['05', 'Momspliktig försäljning (underlag, utan moms)', for (final b in base) m(b), m(Money.sum(base))],
      ['10-12', 'Utgående moms', for (final o in out) m(o), m(outTotal)],
      ['42', 'Övrig försäljning utan moms', '', '', '', m(sales(3004) + sales(3000))],
      ['48', 'Ingående moms att dra av', '', '', '', m(input)],
    ],
    totals: ['49', outTotal >= input ? 'Moms att betala (10-12 minus 48)' : 'Moms att få tillbaka (10-12 minus 48)', '', '', '', m(outTotal - input)],
  );
}

/// What to look at before the package goes to the accountant.
ReportTable controlTable(List<(String, String, String)> checks, String period) => ReportTable(
      title: 'Kontroll inför redovisning $period',
      fileName: 'kontrollrapport_${period.replaceAll(' ', '_')}',
      headers: const ['Kontroll', 'Resultat', 'Att göra'],
      rows: [for (final c in checks) [c.$1, c.$2, c.$3]],
    );
