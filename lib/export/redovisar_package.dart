import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app/app_controller.dart';
import '../data/balances_store.dart';
import '../domain/balances.dart';
import '../domain/closed_days.dart';
import '../domain/dates.dart';
import '../domain/ledger.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/report_period.dart';
import '../domain/reports.dart';
import '../ui/widgets/common.dart';
import 'cash_report.dart';
import 'monthly_pdf.dart';
import 'sie_export.dart';
import 'table_export.dart';

/// One document of the package for the accountant. Table items can be printed
/// and are saved as PDF and Excel; the SIE item is a file only.
class PackageItem {
  final String id;
  final String title;
  final String detail;

  /// The paper version; null for the SIE file.
  final ReportTable? table;

  /// The monthly report keeps its own PDF layout.
  final bool monthly;
  final Uint8List? sie;
  final String? sieName;

  /// Set when the document cannot be made, or something should be checked first.
  final String? problem;

  /// What the button on a problem opens: 'balances', or null.
  final String? action;

  /// False when the document is left out of the package.
  final bool included;
  const PackageItem({
    required this.id,
    required this.title,
    required this.detail,
    this.table,
    this.monthly = false,
    this.sie,
    this.sieName,
    this.problem,
    this.action,
    this.included = true,
  });
}

/// Where a point to look at can be fixed.
enum IssueTarget { zReport, invoice, balances, none }

/// One thing to look at before the package is handed over. Shown in the list that
/// opens from a yellow row; a tap opens the document or page where it is fixed.
class ReviewIssue {
  final String text;
  final IssueTarget target;
  final int? id;
  final Invoice? invoice;
  const ReviewIssue(this.text, this.target, {this.id, this.invoice});
}

class PackageData {
  final ReportPeriod period;
  final BusinessProfile profile;

  /// Only for a one-month period: the monthly report has its own PDF.
  final MonthData? month;
  final List<PackageItem> items;
  final bool hasVerifications;

  /// Everything yellow in the package, with where to fix it.
  final List<ReviewIssue> issues;

  /// Ids of the yellow items the owner has confirmed to send as they are.
  final Set<String> accepted = {};
  PackageData(this.period, this.profile, this.month, this.items, this.hasVerifications, {this.issues = const []});

  String get folderName => 'Redovisarpaket ${period.fileTag}';

  /// A yellow item (something to look at or fill in) that can be confirmed.
  static bool needsOk(PackageItem i) => i.problem != null && i.problem != 'Tom';

  /// Goes into the package: not left out, not empty, and when yellow only after the
  /// owner confirmed it.
  bool selected(PackageItem i) => i.included && i.problem != 'Tom' && (!needsOk(i) || accepted.contains(i.id));

  List<PackageItem> get printable => [
        for (final i in allItems) if (i.table != null && i.included && (i.problem == 'Tom' || selected(i))) i,
      ];

  /// The documents the list shows: the fixed ones and, when there is anything to
  /// look at, the page "Att känna till" for the accountant.
  List<PackageItem> get allItems => [...items, ?issuesItem];

  /// "Att känna till": every open point and what the owner confirmed, as a paper for
  /// the accountant. Built from the state now, so it follows the owner's confirmation.
  PackageItem? get issuesItem {
    if (issues.isEmpty) return null;
    return PackageItem(
      id: 'attkanna',
      title: 'Att känna till',
      detail: accepted.isEmpty ? '${issues.length} ${issues.length == 1 ? 'punkt' : 'punkter'} som inte är klara' : 'Punkter du har godkänt',
      table: ReportTable(
        title: 'Att känna till ${period.title}',
        fileName: 'att_kanna_till_${period.fileTag}',
        headers: const ['Punkt', 'Status'],
        rows: [for (final i in issues) [i.text, accepted.isEmpty ? 'Öppen' : 'Godkänd av ägaren']],
      ),
    );
  }

  /// Where the package stands, for the line at the top of the page.
  PackageStatus get status {
    if (!hasVerifications) return PackageStatus.empty;
    final yellow = [for (final i in items) if (needsOk(i) && i.included) i];
    if (yellow.isEmpty && issues.isEmpty) return PackageStatus.ready;
    if (yellow.isNotEmpty && yellow.every((i) => accepted.contains(i.id))) return PackageStatus.accepted;
    if (yellow.isEmpty) return PackageStatus.ready;
    return PackageStatus.open;
  }

  /// Points still open, for "N saker att se över".
  int get openCount => status == PackageStatus.open ? issues.length : 0;
}

/// Where a package stands before it is sent.
enum PackageStatus {
  /// Nothing registered for the period.
  empty,

  /// Nothing yellow.
  ready,

  /// Something yellow, and the owner confirmed to send it as it is.
  accepted,

  /// Something yellow that the owner has not dealt with.
  open,
}

/// Builds every document the package holds for [period], from what is
/// registered in the app. Documents that need more from the owner come back
/// with a problem.
Future<PackageData> loadPackage(AppController c, ReportPeriod period) async {
  final repo = c.repo;
  final profile = await repo.profile();
  final from = period.from, to = period.to;
  final isMonth = period.kind == PeriodKind.month;
  final month = isMonth ? await MonthData.load(c, YearMonth(period.fromDate.year, period.fromDate.month)) : null;

  final sales = month?.sales ?? await repo.dailySalesBetween(from, to);
  final online = month?.online ?? await repo.onlineSalesBetween(from, to);
  final payslips = month?.payslips ?? await repo.payslipsBetween(from, to);
  final upToEnd = await repo.invoicesBetween('2000-01-01', to);
  final inPeriod = [for (final i in upToEnd) if (i.bookingDate.compareTo(from) >= 0 && i.bookingDate.compareTo(to) <= 0) i];

  final form = await repo.companyForm();
  final vouchers =
      SieExport.vouchers(fromIso: from, toIso: to, sales: sales, invoices: upToEnd, online: online, payslips: payslips, form: form);
  final ledger = Ledger.of(vouchers);
  final title = period.title;
  final empty = vouchers.isEmpty;
  const none = 'Inga verifikationer i perioden. Skanna dokument för perioden.';

  // The balance sheet: opening balances plus the verifications from their date.
  final balances = await loadBalances(repo);
  PackageItem balanceItem;
  if (balances.isEmpty) {
    balanceItem = const PackageItem(
      id: 'balans',
      title: 'Balansräkning (utkast)',
      detail: 'Saknas: ingående balanser',
      problem: 'Fyll i',
      action: 'balances',
      included: false,
    );
  } else if (balances.date.compareTo(to) > 0) {
    balanceItem = PackageItem(
      id: 'balans',
      title: 'Balansräkning (utkast)',
      detail: 'Dina ingående balanser gäller från ${balances.date}, efter perioden',
      problem: 'Se över',
      action: 'balances',
      included: false,
    );
  } else {
    final bl = Ledger.of(SieExport.vouchers(
      fromIso: balances.date,
      toIso: to,
      sales: await repo.dailySalesBetween(balances.date, to),
      invoices: upToEnd,
      online: await repo.onlineSalesBetween(balances.date, to),
      payslips: await repo.payslipsBetween(balances.date, to),
      form: form,
    ));
    final sheet = BalanceSheet.build(balances, bl, to);
    balanceItem = PackageItem(
      id: 'balans',
      title: 'Balansräkning (utkast)',
      detail: sheet.balances ? 'PDF + Excel' : 'Summorna stämmer inte, kontrollera balanserna',
      table: balanceSheetTable(sheet),
      problem: sheet.balances ? null : 'Se över',
      action: sheet.balances ? null : 'balances',
    );
  }

  // The control report: what to look at before handing over.
  final closed = await repo.closedDays();
  final missing = <String>[];
  var scanned = 0, counted = 0;
  for (final (y, m) in period.months) {
    final cov = ZCoverage.of(
      year: y,
      month: m,
      today: DateTime.now(),
      scannedDates: {for (final d in sales) d.businessDate},
      closed: closed,
    );
    scanned += cov.scanned;
    counted += cov.days;
    missing.addAll(cov.missing);
  }
  final differences = [for (final s in sales) if (!s.reportedTotal.isZero && !s.difference.isZero) s.businessDate];
  final incomplete = inPeriod.where((i) => i.isIncomplete).toList();
  final checks = <(String, String, String)>[
    ('Z-rapport för alla öppna dagar', '$scanned av $counted', missing.isEmpty ? 'OK' : 'Saknas: ${missing.take(8).join(', ')}${missing.length > 8 ? ' ...' : ''}'),
    ('Z-rapport som skiljer sig från raderna', '${differences.length}', differences.isEmpty ? 'OK' : differences.join(', ')),
    (
      'Fakturor med uppgifter att fylla i',
      '${incomplete.length}',
      incomplete.isEmpty ? 'OK' : incomplete.map((i) => i.supplier.isEmpty ? 'okänd leverantör' : i.supplier).take(4).join(', ')
    ),
    ('Ingående balanser', balances.isEmpty ? 'Saknas' : 'Finns', balances.isEmpty ? 'Fyll i under Inställningar → Företag' : 'OK'),
  ];
  final issues = checks.where((c) => c.$3 != 'OK').length;
  final controlDetail = missing.isNotEmpty
      ? '${missing.length} ${missing.length == 1 ? 'dag saknar' : 'dagar saknar'} Z-rapport'
      : issues > 0
          ? '$issues saker att se över'
          : 'Allt ser bra ut';

  final sieText = SieExport.build(
    profile: profile,
    fromIso: from,
    toIso: to,
    yearStartIso: period.yearFrom,
    yearEndIso: period.yearTo,
    sales: sales,
    invoices: upToEnd,
    online: online,
    payslips: payslips,
    form: form,
  );

  // Month by month inside the period (the monthly report when it is one month).
  PackageItem overview;
  if (month != null) {
    final r = month.report;
    final noData = r.rows.isEmpty && r.onlineCount == 0;
    overview = PackageItem(
      id: 'manad',
      title: 'Månadsrapport',
      detail: noData ? 'Inga registreringar i månaden' : 'PDF + Excel',
      table: monthlyTable(r),
      monthly: true,
      problem: noData ? 'Tom' : null,
    );
  } else {
    final rows = <YearRow>[];
    for (final y in {for (final (y, _) in period.months) y}) {
      final yr = const ReportGenerator().yearly(
        year: y,
        sales: await repo.dailySalesBetween('$y-01-01', '$y-12-31'),
        invoices: await repo.invoicesForReports('$y-01-01', '$y-12-31'),
        online: await repo.onlineSalesBetween('$y-01-01', '$y-12-31'),
      );
      for (final (py, pm) in period.months) {
        if (py == y) rows.add(yr.rows[pm - 1]);
      }
    }
    final noData = rows.every((r) => r.sales.isZero && r.expenses.isZero && r.online.isZero);
    String m(Money v) => excelNumber(v);
    overview = PackageItem(
      id: 'period',
      title: 'Periodrapport',
      detail: noData ? 'Inga registreringar i perioden' : 'Månad för månad, PDF + Excel',
      table: ReportTable(
        title: 'Periodrapport $title',
        fileName: 'periodrapport_${period.fileTag}',
        headers: const ['Månad', 'Försäljning', 'Varav online', 'Utgifter', 'Utgående moms', 'Ingående moms', 'Momsskillnad'],
        rows: [for (final r in rows) [r.monthName, m(r.sales), m(r.online), m(r.expenses), m(r.outputVat), m(r.inputVat), m(r.vatDifference)]],
        totals: [
          'Totalt',
          m(Money.sum(rows.map((r) => r.sales))),
          m(Money.sum(rows.map((r) => r.online))),
          m(Money.sum(rows.map((r) => r.expenses))),
          m(Money.sum(rows.map((r) => r.outputVat))),
          m(Money.sum(rows.map((r) => r.inputVat))),
          m(Money.sum(rows.map((r) => r.vatDifference))),
        ],
      ),
      problem: noData ? 'Tom' : null,
    );
  }

  final cashDays = sales.where((s) => s.hasCashData).toList();
  PackageItem ledgerItem(String id, String name, ReportTable Function(Ledger, String) build) =>
      PackageItem(id: id, title: name, detail: empty ? none : 'PDF + Excel', table: build(ledger, title), problem: empty ? 'Tom' : null);

  final items = <PackageItem>[
    overview,
    PackageItem(
        id: 'moms',
        title: 'Momsunderlag',
        detail: empty ? none : 'Rutor 05, 10-12, 48, 49',
        table: vatBasisTable(ledger, title),
        problem: empty ? 'Tom' : null),
    PackageItem(
      id: 'kassa',
      title: 'Kassarapport',
      detail: cashDays.isEmpty ? 'Inga Z-rapporter med kontant och kort i perioden' : 'Kontant och kort per dag, PDF + Excel',
      table: cashReportTable(sales, title),
      problem: cashDays.isEmpty ? 'Tom' : null,
    ),
    ledgerItem('ver', 'Verifikationslista', voucherListTable),
    ledgerItem('huvudbok', 'Huvudbok', generalLedgerTable),
    ledgerItem('saldo', 'Saldobalans', trialBalanceTable),
    ledgerItem('resultat', 'Resultaträkning', incomeStatementTable),
    PackageItem(
      id: 'sie',
      title: 'SIE-fil',
      detail: empty ? none : 'Fortnox, Visma, Bokio',
      sie: SieExport.encode(sieText),
      sieName: 'sie_${period.fileTag}.se',
      problem: empty ? 'Tom' : null,
    ),
    balanceItem,
    PackageItem(
      id: 'kontroll',
      title: 'Kontrollrapport',
      detail: controlDetail,
      table: controlTable(checks, title),
      problem: issues > 0 ? 'Se över' : null,
    ),
  ];
  final issueList = <ReviewIssue>[
    for (final s in sales)
      if (!s.reportedTotal.isZero && !s.difference.isZero)
        ReviewIssue('Z-rapport ${s.businessDate}: raderna skiljer ${s.difference.format()} mot dagsförsäljningen', IssueTarget.zReport, id: s.id),
    for (final d in missing.take(10)) ReviewIssue('Z-rapport saknas för $d', IssueTarget.none),
    if (missing.length > 10) ReviewIssue('… och ${missing.length - 10} dagar till saknar Z-rapport', IssueTarget.none),
    for (final i in incomplete)
      ReviewIssue('${i.supplier.isEmpty ? 'Okänd leverantör' : i.supplier}: fyll i ${i.missingFields.join(', ')}', IssueTarget.invoice, invoice: i),
    if (balanceItem.problem != null) ReviewIssue('${balanceItem.title}: ${balanceItem.detail}', IssueTarget.balances),
  ];
  return PackageData(period, profile, month, items, !empty, issues: issueList);
}

/// The files of one item as (file name, bytes): PDF and Excel, or the SIE file.
Future<List<(String, Uint8List)>> itemFiles(PackageData d, PackageItem i) async {
  if (i.sie != null) return [(i.sieName ?? 'sie.se', i.sie!)];
  final t = i.table;
  if (t == null) return const [];
  final month = d.month;
  final pdf = i.monthly && month != null ? await buildMonthlyPdf(month.report, d.profile) : await t.toPdf(d.profile);
  return [('${t.fileName}.pdf', pdf), ('${t.fileName}.csv', t.toCsv())];
}

/// The items that go into the package: included, and not empty.
List<PackageItem> packageContents(PackageData d) => [for (final i in d.allItems) if (d.selected(i)) i];

/// The package as a ZIP with one folder, ready to save or send.
Future<Uint8List> zipPackage(PackageData d, {required String readme}) async {
  final archive = Archive();
  void add(String name, Uint8List bytes) => archive.addFile(ArchiveFile('${d.folderName}/$name', bytes.length, bytes));
  for (final i in packageContents(d)) {
    for (final (name, bytes) in await itemFiles(d, i)) {
      add(name, bytes);
    }
  }
  add('LÄSMIG.txt', Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(readme)]));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// The status line in words, for the page and the README.
String packageStatusText(PackageData d) => switch (d.status) {
      PackageStatus.empty => 'Inget registrerat för perioden',
      PackageStatus.ready => 'Klart att skicka',
      PackageStatus.accepted => 'Klart, med ${d.issues.length} ${d.issues.length == 1 ? 'punkt' : 'punkter'} som ägaren har godkänt',
      PackageStatus.open => d.issues.isEmpty ? 'Något att se över' : '${d.issues.length} ${d.issues.length == 1 ? 'sak' : 'saker'} att se över',
    };

/// The README inside the package. [message] is the owner's text to the accountant.
String packageReadme(PackageData d, {String message = ''}) => [
      d.folderName,
      '',
      'Företag: ${d.profile.name}${d.profile.orgNumber.isEmpty ? '' : ' (${d.profile.orgNumber})'}',
      'Period: ${d.period.title} (${d.period.from} - ${d.period.to})',
      'Skapad: ${SwedishDates.iso(DateTime.now())} med Quee',
      'Status: ${packageStatusText(d)}',
      '',
      'Innehåll:',
      for (final i in packageContents(d)) '- ${i.title}',
      if (d.issues.isNotEmpty) ...[
        '',
        'Att känna till:',
        for (final i in d.issues) '- ${i.text}',
      ],
      if (message.trim().isNotEmpty) ...[
        '',
        'Meddelande från ägaren:',
        message.trim().replaceAll('\r\n', '\n').replaceAll('\n', '\r\n'),
      ],
      '',
      'Allt bygger på det som är registrerat i Quee. Beräknad moms är inte en momsdeklaration.',
      'Balansräkning och avskrivningar är utkast som din redovisare avgör.',
    ].join('\r\n');

/// The e-mail text to the accountant.
String packageMailBody(PackageData d, {required String greeting, required String ownerEmail}) {
  final company = d.profile.name.trim().isEmpty ? 'Quee' : d.profile.name.trim();
  return [
    greeting.isEmpty ? 'Hej!' : 'Hej $greeting!',
    '',
    'Här kommer underlag för ${d.period.title} (${d.period.from} - ${d.period.to}) från $company: rapporter som PDF och Excel samt SIE-fil.',
    if (d.issues.isNotEmpty) ...[
      '',
      d.status == PackageStatus.accepted
          ? 'Att känna till (jag har tagit del av punkterna och skickar underlaget som det är):'
          : 'Det här är inte klart ännu:',
      for (final i in d.issues) '- ${i.text}',
    ] else if (d.status == PackageStatus.ready) ...[
      '',
      'Allt ser komplett ut.',
    ],
    '',
    'Hör av dig om något saknas.',
    '',
    'Vänliga hälsningar',
    company,
    if (ownerEmail.isNotEmpty) ownerEmail,
  ].join('\n');
}

/// The SMS text that tells the accountant the mail is on its way.
String packageSmsText(PackageData d, {required String greeting, required String email}) {
  final company = d.profile.name.trim().isEmpty ? 'Quee' : d.profile.name.trim();
  return '${greeting.isEmpty ? 'Hej!' : 'Hej $greeting!'} Jag har mejlat underlag för ${d.period.title} från $company${email.isEmpty ? '' : ' till $email'}. /$company';
}

/// Several reports as one PDF, for printing in one go.
Future<Uint8List> combinedPdf(List<ReportTable> tables, BusinessProfile profile) async {
  final doc = pw.Document(title: 'Redovisarpaket', author: profile.name);
  final created = DateTime.now();
  for (final t in tables) {
    t.addTo(doc, profile, created);
  }
  return doc.save();
}
