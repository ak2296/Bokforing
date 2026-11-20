import 'package:bokforing/domain/ledger.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/report_period.dart';
import 'package:bokforing/export/moms_xml.dart';
import 'package:bokforing/export/sie_export.dart';
import 'package:flutter_test/flutter_test.dart';

Ledger _ledger(Map<int, double> credits, {Map<int, double> debits = const {}}) {
  Money kr(double v) => Money((v * 100).round());
  final rows = [
    for (final e in credits.entries) SieRow(e.key, 'k${e.key}', -kr(e.value)),
    for (final e in debits.entries) SieRow(e.key, 'k${e.key}', kr(e.value)),
  ];
  return Ledger.of([SieVoucher('A', 1, '2026-10-05', 'test', rows)]);
}

const _oct = ReportPeriod(PeriodKind.month, 2026, 9, 1);

void main() {
  test('moms to pay: boxes, order, no spaces, ISO-8859-1 header', () {
    final l = _ledger({3001: 100000, 2611: 25000}, debits: {2641: 1000});
    final r = VatReturn.fromLedger(l, _oct, '556000-0175');
    expect(r.toPay, 24000);
    expect(r.toXml().split('\r\n'), [
      '<?xml version="1.0" encoding="ISO-8859-1"?>',
      '<eSKDUpload Version="6.0">',
      '<OrgNr>556000-0175</OrgNr>',
      '<Moms>',
      '<Period>202610</Period>',
      '<ForsMomsEjAnnan>100000</ForsMomsEjAnnan>',
      '<MomsUtgHog>25000</MomsUtgHog>',
      '<MomsIngAvdr>1000</MomsIngAvdr>',
      '<MomsBetala>24000</MomsBetala>',
      '</Moms>',
      '</eSKDUpload>',
    ]);
    expect(r.toXml().contains(' <'), isFalse);
    expect(r.toXml().contains('\t'), isFalse);
  });

  test('moms to get back is written with a minus right before the amount', () {
    final l = _ledger({3001: 100000, 2611: 25000}, debits: {2641: 55000});
    final r = VatReturn.fromLedger(l, _oct, '556000-0175');
    expect(r.toPay, -30000);
    expect(r.toXml(), contains('<MomsBetala>-30000</MomsBetala>'));
    expect(r.boxes.last, ('49', 'Moms att få tillbaka', -30000, false));
  });

  test('own figures: added in form order, ruta 49 follows the official formula', () {
    final l = _ledger({3001: 100000, 2611: 25000}, debits: {2641: 1000});
    final r = VatReturn.fromLedger(l, _oct, '556000-0175', manual: {21: 8000, 30: 2000, 35: 12000, 48: 2000});
    expect(r.input, 3000);
    expect(r.toPay, 25000 + 2000 - 3000);
    expect(r.toXml().split('\r\n').sublist(5, 12), [
      '<ForsMomsEjAnnan>100000</ForsMomsEjAnnan>',
      '<MomsUtgHog>25000</MomsUtgHog>',
      '<InkopTjanstAnnatEg>8000</InkopTjanstAnnatEg>',
      '<MomsInkopUtgHog>2000</MomsInkopUtgHog>',
      '<ForsVaruAnnatEg>12000</ForsVaruAnnatEg>',
      '<MomsIngAvdr>3000</MomsIngAvdr>',
      '<MomsBetala>24000</MomsBetala>',
    ]);
    expect(r.manualBoxes, {21, 30, 35, 48});
    expect(r.boxes.where((b) => b.$4).map((b) => b.$1), ['21', '30', '35', '48']);
  });

  test('import VAT (60-62) counts into ruta 49; a typed 42 is added to what the ledger found', () {
    final l = _ledger({3004: 500});
    final r = VatReturn.fromLedger(l, _oct, '556000-0175', manual: {60: 700, 42: 100, 50: 2800});
    expect(r.other, 600);
    expect(r.toPay, 700);
    final x = r.toXml();
    expect(x.indexOf('<ForsOvrigt>600'), lessThan(x.indexOf('<MomsUlagImport>2800')));
    expect(x.indexOf('<MomsUlagImport>2800'), lessThan(x.indexOf('<MomsImportUtgHog>700')));
  });

  test('every box on the entry page goes into the element named for it', () {
    final all = {for (final g in vatManualGroups) for (final f in g.fields) f.box: f.box * 10};
    final r = VatReturn.fromLedger(Ledger.of(const []), _oct, '556000-0175', manual: all);
    for (final g in vatManualGroups) {
      for (final f in g.fields) {
        expect(r.toXml(), contains('<${f.element}>${f.box * 10}</${f.element}>'), reason: 'ruta ${f.box}');
      }
    }
  });

  test('zero typed figures change nothing', () {
    final l = _ledger({3001: 1000, 2611: 250});
    final a = VatReturn.fromLedger(l, _oct, '556000-0175');
    final b = VatReturn.fromLedger(l, _oct, '556000-0175', manual: {21: 0});
    expect(b.toXml(), a.toXml());
    expect(b.manualBoxes, isEmpty);
  });

  test('nothing registered: only the period and ruta 49 = 0', () {
    final r = VatReturn.fromLedger(Ledger.of(const []), _oct, '556000-0175');
    expect(r.toXml().split('\r\n').sublist(3, 7), ['<Moms>', '<Period>202610</Period>', '<MomsBetala>0</MomsBetala>', '</Moms>']);
  });

  test('ore are rounded per box and ruta 49 follows the rounded boxes', () {
    // 12 % 100.50 -> 101, 25 % 250.49 -> 250, input 99.50 -> 100: 49 = 101 + 250 - 100
    final l = _ledger({2621: 100.50, 2611: 250.49}, debits: {2641: 99.50});
    final r = VatReturn.fromLedger(l, _oct, '556000-0175');
    expect((r.outMid, r.outHigh, r.input), (101, 250, 100));
    expect(r.toPay, 251);
  });

  test('period: quarter and year use the last month', () {
    final l = Ledger.of(const []);
    expect(VatReturn.fromLedger(l, const ReportPeriod(PeriodKind.quarter, 2026, 3, 1), '556000-0175').period, '202612');
    expect(VatReturn.fromLedger(l, const ReportPeriod(PeriodKind.year, 2026, 0, 1), '556000-0175').period, '202612');
    expect(VatReturn.supports(PeriodKind.half), isFalse);
  });

  test('org number: hyphen added, 12 digits cut to 10, nonsense refused', () {
    expect(VatReturn.normaliseOrgNr('5560000175'), '556000-0175');
    expect(VatReturn.normaliseOrgNr('556000-0175'), '556000-0175');
    expect(VatReturn.normaliseOrgNr('19800101-1234'), '800101-1234');
    expect(VatReturn.normaliseOrgNr('123'), isNull);
    expect(VatReturn.normaliseOrgNr(''), isNull);
  });

  test('bytes are ISO-8859-1 and the file is named after the period', () {
    final r = VatReturn.fromLedger(Ledger.of(const []), _oct, '556000-0175');
    expect(r.toBytes().every((b) => b < 128), isTrue);
    expect(r.fileName, 'momsdeklaration_202610.xml');
  });
}
