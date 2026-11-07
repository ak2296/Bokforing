import 'package:bokforing/data/storage.dart';
import 'package:bokforing/imaging/preprocess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('A saved photo copy is at most 1600 pixels and smaller', () {
    final page = img.Image(width: 2400, height: 3200);
    img.fill(page, color: img.ColorRgb8(245, 245, 240));
    for (var y = 100; y < 3100; y += 60) {
      img.drawLine(page, x1: 120, y1: y, x2: 2200, y2: y, color: img.ColorRgb8(20, 20, 20), thickness: 4);
    }
    final original = img.encodeJpg(page, quality: 92);
    final small = compactJpeg(original);
    final decoded = img.decodeJpg(small)!;
    expect(decoded.height, 1600);
    expect(decoded.width, 1200);
    expect(small.length, lessThan(original.length));
  });

  test('Sizes are shown in kB and MB', () {
    expect(AppStorage.format(512 * 1024), '512 kB');
    expect(AppStorage.format(5 * 1024 * 1024 + 300 * 1024), '5,3 MB');
    expect(AppStorage.format(119 * 1024 * 1024), '119 MB');
  });
}
