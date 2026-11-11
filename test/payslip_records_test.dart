import 'package:bokforing/app/settings_keys.dart';
import 'package:bokforing/data/database.dart';
import 'package:bokforing/data/repository.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/reports.dart';
import 'package:bokforing/domain/result_report.dart';
import 'package:bokforing/export/backup.dart';
import 'package:bokforing/export/sie_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Made-up employee and pay.
Payslip _slip({
  String date = '2026-10-27',
  int gross = 1850000,
  int fee = 581300,
  int tax = 410000,
  String name = 'Anna Exempel',
  String pnr = '121212-1212',
}) =>
    Payslip(
      payoutDate: date,
      periodFrom: '2026-10-01',
      periodTo: '2026-10-31',
      gross: Money(gross),
      employerFee: Money(fee),
      tax: Money(tax),
      employeeName: name,
      personnummer: pnr,
      meta: const RecordMeta(source: RecordSource.manual),
    );

void main() {
  test('the cost is bruttolön plus arbetsgivaravgift; the tax is not a cost on top', () {
    final p = _slip();
    expect(p.cost, const Money(2431300));
    expect(p.net, const Money(1440000));
    final e = p.asExpenses();
    expect(e.map((i) => i.costType), ['loner', 'sociala']);
    expect(e.map((i) => i.total), [const Money(1850000), const Money(581300)]);
    expect(e.every((i) => i.vatTotal.isZero && i.paid && i.invoiceDate == '2026-10-27'), isTrue);
  });

  test('reports add the payslip as an expense without moms, on the payout date', () {
    final r = const ReportGenerator().monthly(
        year: 2026, month: 10, categories: const [], sales: const [], invoices: _slip().asExpenses(), online: const []);
    expect(r.totalExpenses, const Money(2431300));
    expect(r.totalInputVat, Money.zero);
  });

  test('the resultatrapport shows Löner and Sociala avgifter', () {
    final r = ResultReport.build(
        title: 'Oktober 2026',
        fromIso: '2026-10-01',
        toIso: '2026-10-31',
        sales: const [],
        invoices: _slip().asExpenses());
    expect(r.costs.map((c) => c.label), ['Löner', 'Sociala avgifter']);
    expect(r.totalCosts, const Money(2431300));
  });

  group('stored', () {
    late Repository repo;
    setUpAll(sqfliteFfiInit);
    setUp(() async {
      repo = Repository(await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
    });
    tearDown(() => repo.db.close());

    test('save, read back, list by payout date, delete', () async {
      final id = await repo.savePayslip(_slip());
      final back = (await repo.payslip(id))!;
      expect(back.employeeName, 'Anna Exempel');
      expect(back.personnummer, '121212-1212');
      expect(back.periodFrom, '2026-10-01');
      expect(back.gross, const Money(1850000));
      expect(back.tax, const Money(410000));
      expect(await repo.payslipsBetween('2026-10-01', '2026-10-31'), hasLength(1));
      expect(await repo.payslipsBetween('2026-11-01', '2026-11-30'), isEmpty);
      await repo.deletePayslip(id);
      expect(await repo.payslip(id), isNull);
    });

    test('an edit keeps one record and is marked as edited', () async {
      final id = await repo.savePayslip(_slip());
      await repo.savePayslip(Payslip(
        id: id,
        payoutDate: '2026-10-27',
        gross: const Money(1900000),
        employerFee: const Money(581300),
        tax: const Money(410000),
        meta: const RecordMeta(source: RecordSource.manual),
      ));
      final back = (await repo.payslip(id))!;
      expect(back.gross, const Money(1900000));
      expect(back.meta.manuallyEdited, isTrue);
      expect(await repo.payslipsBetween('2026-10-01', '2026-10-31'), hasLength(1));
    });

    test('the same person paid the same amount the same day is a duplicate', () async {
      await repo.savePayslip(_slip());
      expect(await repo.findDuplicatePayslips(_slip()), hasLength(1));
      expect(await repo.findDuplicatePayslips(_slip(gross: 1900000)), isEmpty);
      expect(await repo.findDuplicatePayslips(_slip(date: '2026-11-27')), isEmpty);
    });

    test('invoicesForReports has the payslip as two expenses, rounded when that is on', () async {
      await repo.savePayslip(_slip(gross: 1850050, fee: 581349));
      var list = await repo.invoicesForReports('2026-10-01', '2026-10-31');
      expect(list.map((i) => i.total), [const Money(1850050), const Money(581349)]);
      await repo.setBoolSetting(SettingsKeys.roundExpenses, true);
      list = await repo.invoicesForReports('2026-10-01', '2026-10-31');
      expect(list.map((i) => i.total), [const Money(1850100), const Money(581300)]);
      // Never among the real invoices: not in the unpaid list or the checks of what is missing.
      expect(await repo.invoicesBetween('2026-10-01', '2026-10-31'), isEmpty);
      expect(await repo.unpaidInvoices(), isEmpty);
    });

    test('recent registrations and the document count include it, with the name only', () async {
      await repo.savePayslip(_slip());
      final recent = await repo.recentRegistrations();
      expect(recent.single.kind, 'payslip');
      expect(recent.single.typeLabel, 'Lönebesked');
      expect(recent.single.title, 'Anna Exempel');
      expect(recent.single.amount, const Money(2431300));
      expect(await repo.documentCount(), 1);
    });

    test('a backup holds the payslips', () async {
      await repo.savePayslip(_slip());
      final backup = await Backup.collect(repo.db);
      expect((backup['tables'] as Map)['payslips'], hasLength(1));
    });
  });

  group('SIE', () {
    String build(List<Payslip> payslips, {String from = '2026-10-01', String to = '2026-10-31'}) => SieExport.build(
        profile: const BusinessProfile(name: 'Ankan AB'),
        fromIso: from,
        toIso: to,
        yearStartIso: '2026-01-01',
        yearEndIso: '2026-12-31',
        sales: const [],
        invoices: const [],
        payslips: payslips,
        generated: DateTime(2026, 11, 1));

    /// Each verification's transactions, as öre.
    List<List<int>> verifications(String sie) {
      final out = <List<int>>[];
      List<int>? current;
      for (final l in sie.split('\r\n')) {
        if (l.startsWith('#VER')) current = [];
        final m = RegExp(r'#TRANS \d+ \{\} (-?\d+)\.(\d{2})').firstMatch(l);
        if (m != null && current != null) {
          final v = int.parse(m.group(1)!.replaceAll('-', '')) * 100 + int.parse(m.group(2)!);
          current.add(l.contains(' {} -') ? -v : v);
        }
        if (l == '}' && current != null) out.add(current);
      }
      return out;
    }

    test('one balanced verification per payslip', () {
      final sie = build([_slip(), _slip(date: '2026-10-28', gross: 1000000, fee: 314200, tax: 200000, name: 'Bo Prov')]);
      final vers = verifications(sie);
      expect(vers, hasLength(2));
      for (final v in vers) {
        expect(v.fold<int>(0, (a, b) => a + b), 0);
      }
    });

    test('lön, avgift, personalskatt, avräkning and bank; no personnummer', () {
      final sie = build([_slip()]);
      for (final a in ['7010', '7510', '2710', '2731', '1930']) {
        expect(sie, contains('#TRANS $a {}'));
      }
      expect(sie, contains('Lönebesked Anna Exempel'));
      expect(sie, isNot(contains('121212')));
      expect(sie, contains('#KONTO 2710'));
    });

    test('only payslips paid out in the period', () {
      expect(verifications(build([_slip(date: '2026-09-28')])), isEmpty);
    });
  });
}
