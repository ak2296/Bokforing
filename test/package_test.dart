import 'package:bokforing/domain/models.dart';
import 'package:bokforing/export/redovisar_package.dart';
import 'package:bokforing/export/table_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const profile = BusinessProfile(name: 'Test AB', orgNumber: '556123-4567', address: '');
  const a = ReportTable(title: 'A', fileName: 'a', headers: ['x', 'y'], rows: [['1', '2']]);
  final many = ReportTable(title: 'B', fileName: 'b', headers: const ['x', 'y'], rows: [for (var i = 0; i < 120; i++) ['$i', '$i']]);

  test('a short report is one page and a long one takes several', () async {
    expect(await a.pageCount(profile), 1);
    expect(await many.pageCount(profile), greaterThan(1));
  });

  test('several reports become one PDF with all their pages', () async {
    final bytes = await combinedPdf([a, many], profile);
    expect(bytes.length, greaterThan(500));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
