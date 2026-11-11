import 'package:bokforing/app/app_controller.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:bokforing/ui/dashboard_page.dart';
import 'package:bokforing/ui/theme.dart';
import 'package:bokforing/ui/widgets/ledger_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DailySales _day(String date, int kr) => DailySales(
      businessDate: date,
      reportedTotal: Money(kr * 100),
      items: [SalesItem(categoryName: 'Mat', vat: VatRate.twelve, amount: Money(kr * 100))],
      meta: const RecordMeta(source: RecordSource.manual),
    );

void main() {
  test('weekday averages: Monday first, days without a Z-report are not counted', () {
    // 2026-10-05 and 2026-10-12 are Mondays, 2026-10-10 a Saturday.
    final avg = DashboardExtras.weekdayAverage([
      _day('2026-10-05', 1000),
      _day('2026-10-12', 2000),
      _day('2026-10-10', 3000),
    ]);
    expect(avg, [1500, 0, 0, 0, 0, 3000, 0]);
  });

  test('no sales gives all zeros', () {
    expect(DashboardExtras.weekdayAverage(const []), List<double>.filled(7, 0));
  });

  test('the theme setting is read back', () {
    expect(AppController.parseThemeMode('dark'), ThemeMode.dark);
    expect(AppController.parseThemeMode('light'), ThemeMode.light);
    expect(AppController.parseThemeMode('auto'), ThemeMode.system);
    expect(AppController.parseThemeMode(null), ThemeMode.system);
  });

  test('the dark theme has dark surfaces and leaves the colours as they were', () {
    final before = AppTheme.dark;
    final d = AppTheme.darkTheme();
    expect(d.brightness, Brightness.dark);
    expect(d.scaffoldBackgroundColor, const Color(0xFF111917));
    expect(AppTheme.dark, before);
    expect(AppTheme.light().scaffoldBackgroundColor, const Color(0xFFF5F7F4));
  });

  test('neighbouring parts of the share bars alternate dark and light', () {
    for (final p in [salesPalette, costPalette]) {
      for (var i = 1; i < 4; i++) {
        expect((p[i].computeLuminance() - p[i - 1].computeLuminance()).abs(), greaterThan(0.1));
      }
    }
  });
}
