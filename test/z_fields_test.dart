import 'package:bokforing/data/database.dart';
import 'package:bokforing/data/repository.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/ocr_models.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:bokforing/domain/z_report_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _cats = [
  Category(id: 1, name: 'Mat', vat: VatRate.six),
  Category(id: 2, name: 'Konfektyr', vat: VatRate.six),
  Category(id: 3, name: 'Avhämtning', vat: VatRate.six),
];

const _report = 'Z-rapport\nFrån 2026-10-31\nFörsäljning per varugrupp\n'
    'Drycka 163,00\nDrycka avhämtning 70,00\nMat 1 912,00\nMat avhämtning 1 507,00\nPant 12,00\n'
    'Total försäljning 3 664,00';

void main() {
  test('owner rules: several lines add up in one category, ignored lines are not counted', () {
    final d = const ZReportParser(_cats, aliases: {
      'drycka': 2,
      'drycka avhämtning': 3,
      'mat avhämtning': 3,
    }, ignored: {
      'pant'
    }).parse(OcrResult.fromPlainText(_report));
    ZLine line(String l) => d.lines.firstWhere((x) => x.label == l);
    expect(line('Drycka').categoryId, 2);
    expect(line('Drycka avhämtning').categoryId, 3);
    expect(line('Mat avhämtning').categoryId, 3);
    expect(line('Mat').categoryId, 1);
    expect(line('Pant').match, MatchKind.ignored);
    expect(line('Pant').categoryId, isNull);
    final avh = d.lines.where((l) => l.categoryId == 3).map((l) => l.amount);
    expect(Money.sum(avh), Money.kr(1577));
    expect(d.sumWith(const {}), Money.kr(3652));
  });

  test('a line two letters off a rule is only suggested', () {
    final d = const ZReportParser(_cats, aliases: {'drycka avhämtning': 3})
        .parse(OcrResult.fromPlainText('Z-rapport\nVarugrupper\nDrycka avhämtnlnq 70,00\nTotal försäljning 70,00'));
    final l = d.lines.single;
    expect(l.categoryId, isNull);
    expect(l.suggestedCategoryId, 3);
    expect(l.match, MatchKind.possible);
  });

  test('rules are stored, changed and removed', () async {
    sqfliteFfiInit();
    final repo = Repository(await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
    await repo.saveCategories(const [Category(name: 'Avhämtning', vat: VatRate.six)]);
    final id = (await repo.categories()).single.id!;
    await repo.setZLabelRule('Drycka Avhämtning', id);
    await repo.setZLabelRule('Pant', null);
    expect(await repo.zLabelRules(), [
      (label: 'drycka avhämtning', categoryId: id),
      (label: 'pant', categoryId: null),
    ]);
    await repo.setZLabelRule('pant', id);
    expect(await repo.ignoredZLabels(), isEmpty);
    await repo.deleteZLabelRule('pant');
    expect((await repo.zLabelRules()).length, 1);
    await repo.db.close();
  });
}
