import 'package:bokforing/domain/text_merge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('överlappande rader slås ihop', () {
    expect(
        mergeParts(['Rad ett här\nRad två här\nRad tre här', 'Rad två här\nRad tre här\nRad fyra här']),
        'Rad ett här\nRad två här\nRad tre här\nRad fyra här');
  });

  test('ingen överlappning ger enkel sammanfogning', () {
    expect(mergeParts(['Sida ett rad A\nSida ett rad B', 'Sida två rad C']),
        'Sida ett rad A\nSida ett rad B\nSida två rad C');
  });

  test('små OCR-skillnader i överlappningen tolereras', () {
    expect(mergeParts(['Första raden\nTotalt 598,90 kr', 'Totalt 598.90 kr\nSista raden']),
        'Första raden\nTotalt 598,90 kr\nSista raden');
  });

  test('streck och korta rader räknas inte som överlappning', () {
    expect(mergeParts(['Text före\n-----', '-----\nText efter']), 'Text före\n-----\n-----\nText efter');
  });

  test('en enda del lämnas orörd', () {
    expect(mergeParts(['A rad\nB rad']), 'A rad\nB rad');
    expect(mergeParts([]), '');
  });
}
