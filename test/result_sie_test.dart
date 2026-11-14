import 'package:bokforing/domain/cost_types.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/result_report.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:bokforing/export/sie_export.dart';
import 'package:flutter_test/flutter_test.dart';

const _meta = RecordMeta(source: RecordSource.manual);

final _sales = [
  DailySales(
    businessDate: '2026-10-05',
    zNumber: '183',
    reportedTotal: Money.kr(1180),
    items: const [
      SalesItem(categoryName: 'Mat', vat: VatRate.twelve, amount: Money(112000)),
      SalesItem(categoryName: 'Öl', vat: VatRate.twentyFive, amount: Money(6000)),
    ],
    meta: _meta,
  ),
];

final _invoices = [
  Invoice(
      invoiceDate: '2026-10-03',
      supplier: 'Snabbgross',
      total: const Money(125000),
      vatTotal: const Money(25000),
      costType: CostType.goods.key,
      paid: true,
      paidDate: '2026-10-03',
      meta: _meta),
  Invoice(
      invoiceDate: '2026-09-20',
      supplier: 'Telenor',
      invoiceNumber: '526730297326',
      total: const Money(143300),
      vatTotal: const Money(28650),
      costType: CostType.phone.key,
      paid: true,
      paidDate: '2026-10-10',
      meta: _meta),
  Invoice(invoiceDate: '2026-10-20', supplier: 'Okänd', total: const Money(10000), vatTotal: Money.zero, meta: _meta),
];

void main() {
  test('Resultatrapport: sales and costs excl. VAT per cost type', () {
    final r = ResultReport.build(
      title: 'Oktober 2026',
      fromIso: '2026-10-01',
      toIso: '2026-10-31',
      sales: _sales,
      invoices: _invoices,
      online: [OnlineSale(paymentDate: '2026-10-12', partner: 'Foodora', amount: const Money(11200), vat: const Money(1200), vatRate: VatRate.twelve, meta: _meta)],
    );
    // 1120 kr at 12 % is 1000 net; 60 kr at 25 % is 48 net.
    expect(r.cashSales, Money.kr(1048));
    expect(r.onlineSales, Money.kr(100));
    expect(r.costs.map((c) => c.label), ['Varuinköp', 'Ej vald kostnadstyp']);
    expect(r.totalCosts, Money.kr(1100));
    expect(r.result, Money.kr(48));
    expect(r.unclassified, 1);
  });

  test('SIE 4: balanced verifications on BAS accounts, payment of an older invoice', () {
    final text = SieExport.build(
      profile: const BusinessProfile(name: 'Ankan restaurang & pizzeria', orgNumber: '121212-1212'),
      fromIso: '2026-10-01',
      toIso: '2026-10-31',
      yearStartIso: '2026-01-01',
      yearEndIso: '2026-12-31',
      sales: _sales,
      invoices: _invoices,
      generated: DateTime(2026, 11, 7),
    );
    expect(text, contains('#SIETYP 4'));
    expect(text, contains('#RAR 0 20260101 20261231'));
    expect(text, contains('#ORGNR 121212-1212'));
    expect(text, contains('#KONTO 4010 "Varuinköp"'));
    expect(text, contains('#VER A 1 20261005 "Dagskassa Z 183"'));
    expect(text, contains('#TRANS 1910 {} 1180.00'));
    expect(text, contains('#TRANS 3002 {} -1000.00'));
    expect(text, contains('#TRANS 2621 {} -120.00'));
    expect(text, contains('#TRANS 3001 {} -48.00'));
    expect(text, contains('#TRANS 2611 {} -12.00'));
    // A kvitto paid on the day goes straight to the bank.
    expect(text, contains('#TRANS 1930 {} -1250.00'));
    // The September invoice is paid in October: only the payment is here.
    expect(text, isNot(contains('6210')));
    expect(text, contains('"Betalning Telenor nr 526730297326"'));
    // An invoice with no cost type goes to Övriga kostnader, as a debt.
    expect(text, contains('#TRANS 6990 {} 100.00'));
    expect(text, contains('#TRANS 2440 {} -100.00'));

    // Every verification balances.
    var sum = 0, count = 0;
    for (final line in text.split('\r\n')) {
      if (line == '{') sum = 0;
      final t = RegExp(r'#TRANS \d+ \{\} (-?)(\d+)\.(\d{2})$').firstMatch(line.trim());
      if (t != null) sum += (t[1] == '-' ? -1 : 1) * (int.parse(t[2]!) * 100 + int.parse(t[3]!));
      if (line == '}') {
        expect(sum, 0);
        count++;
      }
    }
    expect(count, 4);
    // PC8: å, ä and ö as one byte each.
    final bytes = SieExport.encode('Försäljning åÄ');
    expect(bytes.sublist(1, 2), [0x94]);
    expect(bytes.sublist(bytes.length - 2), [0x86, 0x8E]);
  });

  test('SieExport.vouchers: the same verifications, numbers and lines as the file', () {
    final vouchers = SieExport.vouchers(
      fromIso: '2026-10-01',
      toIso: '2026-10-31',
      sales: _sales,
      invoices: _invoices,
    );
    expect(vouchers.map((v) => '${v.series}${v.number}').toList(), ['C1', 'A1', 'C2', 'C3']);
    final z = vouchers.firstWhere((v) => v.series == 'A');
    expect(z.number, 1);
    expect(z.date, '2026-10-05');
    expect(z.text, 'Dagskassa Z 183');
    expect(z.debit, Money.kr(1180));
    expect(z.credit, Money.kr(1180));
    expect(z.lines.map((r) => r.account), containsAll([1910, 3002, 2621, 3001, 2611]));
    // Every verification balances, and the series are numbered from 1.
    expect(vouchers.every((v) => v.balances), isTrue);
        // The file holds exactly these verifications.
    final text = SieExport.build(
      profile: const BusinessProfile(name: 'Ankan'),
      fromIso: '2026-10-01',
      toIso: '2026-10-31',
      yearStartIso: '2026-01-01',
      yearEndIso: '2026-12-31',
      sales: _sales,
      invoices: _invoices,
    );
    expect(RegExp(r'#VER ').allMatches(text).length, vouchers.length);
    for (final v in vouchers) {
      expect(text, contains('#VER ${v.series} ${v.number} ${v.date.replaceAll('-', '')} '));
    }
  });
}
