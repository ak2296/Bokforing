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

class PackageData {
  final ReportPeriod period;
  final BusinessProfile profile;

  /// Only for a one-month period: the monthly report has its own PDF.
  final MonthData? month;
  final List<PackageItem> items;
  final bool hasVerifications;
  const PackageData(this.period, this.profile, this.month, this.items, this.hasVerifications);

  String get folderName => 'Redovisarpaket ${period.fileTag}';

  List<PackageItem> get printable => [for (final i in items) if (i.table != null && i.included) i];
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

  final vouchers = SieExport.vouchers(fromIso: from, toIso: to, sales: sales, invoices: upToEnd, online: online, payslips: payslips);
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
  return PackageData(period, profile, month, items, !empty);
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
List<PackageItem> packageContents(PackageData d) => [for (final i in d.items) if (i.included && i.problem != 'Tom') i];

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

/// The README inside the package.
String packageReadme(PackageData d) => [
      d.folderName,
      '',
      'Företag: ${d.profile.name}${d.profile.orgNumber.isEmpty ? '' : ' (${d.profile.orgNumber})'}',
      'Period: ${d.period.title} (${d.period.from} - ${d.period.to})',
      'Skapad: ${SwedishDates.iso(DateTime.now())} med Quee',
      '',
      'Innehåll:',
      for (final i in packageContents(d)) '- ${i.title}',
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
