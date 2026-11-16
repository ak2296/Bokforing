import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the contents list has one title for every chapter page of the guide', () {
    final index = jsonDecode(File('assets/guide/index.json').readAsStringSync()) as Map<String, dynamic>;
    final pages = (index['pages'] as List).length;
    final titles = File('assets/anvandarguide_innehall.txt').readAsLinesSync().where((l) => l.trim().isNotEmpty).length;
    // cover + contents + one page per chapter
    expect(titles, pages - 2);
  });

  test('every guide slice exists and is small enough for an old phone to draw', () {
    final index = jsonDecode(File('assets/guide/index.json').readAsStringSync()) as Map<String, dynamic>;
    for (final page in index['pages'] as List) {
      for (final t in page as List) {
        expect(File('assets/guide/${t['f']}').existsSync(), isTrue, reason: '${t['f']}');
        expect(t['h'] as int, lessThanOrEqualTo(2048));
      }
    }
  });
}
