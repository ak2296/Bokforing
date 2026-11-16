import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the contents list has one title for every chapter page of the guide PDF', () {
    final pdf = File('assets/anvandarguide.pdf').readAsBytesSync();
    final pages = RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(pdf)).length;
    final titles = File('assets/anvandarguide_innehall.txt').readAsLinesSync().where((l) => l.trim().isNotEmpty).length;
    // cover + contents + one page per chapter
    expect(titles, pages - 2);
  });
}
