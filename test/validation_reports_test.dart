import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/reports.dart';
import 'package:bokforing/domain/validation.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:flutter_test/flutter_test.dart';

const _meta = RecordMeta(source: RecordSource.manual, confirmed: true);

const _cats = [
  Category(id: 1, name: 'Mat', vat: VatRate.six, sortOrder: 0),
  Category(id: 2, name: 'Konfektyr', vat: VatRate.six, sortOrder: 1),
  Category(id: 3, name: 'Tobak', vat: VatRate.twentyFive, sortOrder: 2),
  Category(id: 4, name: 'Öl', vat: VatRate.twentyFive, sortOrder: 3),
  Category(id: 5, name: 'Sprit', vat: VatRate.twentyFive, sortOrder: 4),
  Category(id: 6, name: 'Vin', vat: VatRate.twentyFive, sortOrder: 5),
  Category(id: 7, name: 'Cider', vat: VatRate.twentyFive, sortOrder: 6),
];

DailySales _day(String date, Map<int, int> kr, int reportedKr) => DailySales(
      businessDate: date,
      reportedTotal: Money.kr(reportedKr),
      items: [
        for (final e in kr.entries)
          SalesItem(
            categoryId: e.key,
            categoryName: _cats.firstWhere((c) => c.id == e.key).name,
            vat: _cats.firstWhere((c) => c.id == e.key).vat,
            amount: Money.kr(e.value),
          ),
      ],
      meta: _meta,
    );

const _example = {1: 4500, 2: 300, 3: 800, 4: 2100, 5: 900, 6: 1700, 7: 500};

void main() {
  const engine = AccountingValidationEngine();

  group('Z-report reconciliation', () {
    test('4500+300+800+2100+900+1700+500 = 10800 matches', () {
      final r = engine.reconcileZReport(_example.values.map(Money.kr), Money.kr(10800));
      expect(r.status, ValidationStatus.ok);
      expect(r.difference, Money.zero);
      expect(r.message, 'Kontroll: detaljerad försäljning stämmer med dagsförsäljningen.');
    });

    test('Öl = 2000 gives difference -100 kr and nothing is changed', () {
      final day = _day('2026-10-28', {..._example, 4: 2000}, 10800);
      final r = engine.reconcileZReport(day.items.map((i) => i.amount), day.reportedTotal);
      expect(r.status, ValidationStatus.warning);
      expect(r.difference, Money.kr(-100));
      expect(day.detailedTotal, Money.kr(10700));
      expect(day.reportedTotal, Money.kr(10800));
    });
  });

  group('Invoice validation', () {
    test('net + VAT = total within öresavrundning', () {
      // Centrumgrossisten: 491,87 + 29,47 = 521,34, att betala 521,00.
      final r = engine.checkInvoiceArithmetic(const Money(49187), const Money(2947), const Money(52100));
      expect(r.status, ValidationStatus.ok);
    });

    test('large difference is a warning', () {
      final r = engine.checkInvoiceArithmetic(Money.kr(1000), Money.kr(250), Money.kr(1300));
      expect(r.status, ValidationStatus.warning);
      expect(r.difference, Money.kr(-50));
    });

    test('VAT breakdown must sum to total VAT', () {
      final lines = [
        InvoiceVatLine(rate: VatRate.twentyFive, vat: Money.kr(250)),
        InvoiceVatLine(rate: VatRate.twelve, vat: Money.kr(120)),
        InvoiceVatLine(rate: VatRate.six, vat: Money.kr(60)),
      ];
      expect(engine.checkVatBreakdown(lines, Money.kr(430)).status, ValidationStatus.ok);
      expect(engine.checkVatBreakdown(lines, Money.kr(400)).status, ValidationStatus.warning);
    });

    test('VAT line checked against its net amount', () {
      const good = InvoiceVatLine(rate: VatRate.twentyFive, vat: Money(998), net: Money(3992));
      expect(engine.checkVatLine(good), isNull);
      const bad = InvoiceVatLine(rate: VatRate.twentyFive, vat: Money(1500), net: Money(3992));
      expect(engine.checkVatLine(bad), isNotNull);
    });

    test('implausible VAT above 25 % share', () {
      expect(engine.checkVatPlausible(Money.kr(300), Money.kr(1000)), isNotNull);
      expect(engine.checkVatPlausible(Money.kr(200), Money.kr(1000)), isNull);
    });
  });

  group('Reports', () {
    final sales = [
      _day('2026-10-01', _example, 10800),
      _day('2026-10-02', {1: 1000, 4: 500}, 1500),
      _day('2026-11-01', {1: 200}, 200),
    ];
    final invoices = [
      Invoice(invoiceDate: '2026-10-01', total: Money.kr(1000), vatTotal: Money.kr(200), meta: _meta),
      Invoice(invoiceDate: '2026-10-01', total: Money.kr(200), vatTotal: Money.kr(40), meta: _meta),
      Invoice(invoiceDate: '2026-10-05', total: Money.kr(106), vatTotal: Money.kr(6), meta: _meta),
    ];

    test('monthly table: dynamic columns, invoices aggregated per day', () {
      final r = const ReportGenerator()
          .monthly(year: 2026, month: 10, categories: _cats, sales: sales, invoices: invoices);
      expect(r.columns.map((c) => c.name).toList(), ['Mat', 'Konfektyr', 'Tobak', 'Öl', 'Sprit', 'Vin', 'Cider']);
      expect(r.rows.map((x) => x.date).toList(), ['2026-10-01', '2026-10-02', '2026-10-05']);
      final first = r.rows.first;
      expect(first.sales, Money.kr(10800));
      expect(first.expenses, Money.kr(1200));
      expect(first.inputVat, Money.kr(240));
      expect(first.invoiceCount, 2);
      expect(r.totalSales, Money.kr(12300));
      expect(r.totalExpenses, Money.kr(1306));
      expect(r.columnTotals['id:1'], Money.kr(5500));
      expect(engine.checkAggregation('sales', r.rows.map((x) => x.sales), r.totalSales).isOk, isTrue);
      expect(r.vatDifference, r.totalOutputVat - r.totalInputVat);
    });

    test('daily output VAT uses the reverse formula per category', () {
      final d = _day('2026-10-02', {1: 1060, 4: 1250}, 2310);
      expect(d.outputVat, Money.kr(60) + Money.kr(250));
    });

    test('columns follow the user categories', () {
      final fewer = [_cats[0], _cats[2], _cats[3], _cats[5]];
      final r = const ReportGenerator()
          .monthly(year: 2026, month: 12, categories: fewer, sales: const [], invoices: const []);
      expect(r.columns.map((c) => c.name).toList(), ['Mat', 'Tobak', 'Öl', 'Vin']);
      final more = [...fewer, const Category(id: 7, name: 'Cider', vat: VatRate.twentyFive, sortOrder: 9)];
      final r2 = const ReportGenerator()
          .monthly(year: 2026, month: 12, categories: more, sales: const [], invoices: const []);
      expect(r2.columns.last.name, 'Cider');
    });

    test('a deactivated category keeps its column when the month has data', () {
      final cats = [..._cats.where((c) => c.id != 7), _cats[6].copyWith(active: false)];
      final r = const ReportGenerator()
          .monthly(year: 2026, month: 10, categories: cats, sales: sales, invoices: invoices);
      expect(r.columns.map((c) => c.name), contains('Cider'));
    });

    test('yearly aggregation', () {
      final y = const ReportGenerator().yearly(year: 2026, sales: sales, invoices: invoices);
      expect(y.rows.length, 12);
      expect(y.rows[9].sales, Money.kr(12300));
      expect(y.rows[10].sales, Money.kr(200));
      expect(y.sales, Money.kr(12500));
      expect(y.expenses, Money.kr(1306));
      expect(y.rows[9].monthName, 'Oktober');
      expect(engine.checkAggregation('year', y.rows.map((r) => r.sales), y.sales).isOk, isTrue);
    });
  });
}
