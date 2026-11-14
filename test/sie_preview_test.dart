import 'package:bokforing/domain/money.dart';
import 'package:bokforing/export/sie_export.dart';
import 'package:bokforing/ui/reports/sie_preview_page.dart';
import 'package:bokforing/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _page(List<SieVoucher> vouchers) =>
    MaterialApp(theme: AppTheme.light(), home: SiePreviewPage(period: 'Oktober 2026', vouchers: vouchers));

void main() {
  testWidgets('shows each verification with its lines and says they balance', (tester) async {
    const v = SieVoucher('A', 1, '2026-10-05', 'Dagskassa Z 183', [
      SieRow(1910, 'Kassa', Money(118000)),
      SieRow(3002, 'Försäljning inom Sverige, 12 % moms', Money(-118000)),
      SieRow(2621, 'Utgående moms', Money.zero),
    ]);
    await tester.pumpWidget(_page([v]));
    expect(find.text('Förhandsvisa SIE'), findsOneWidget);
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('Dagskassa Z 183'), findsOneWidget);
    expect(find.text('1910 Kassa'), findsOneWidget);
    // A line of 0 kr is not in the file, so it is not shown.
    expect(find.textContaining('2621'), findsNothing);
    expect(find.textContaining('Alla verifikationer balanserar'), findsOneWidget);
  });

  testWidgets('warns about a verification that does not balance', (tester) async {
    const v = SieVoucher('C', 1, '2026-10-03', 'Snabbgross', [
      SieRow(4010, 'Varuinköp', Money(100000)),
      SieRow(1930, 'Företagskonto', Money(-90000)),
    ]);
    await tester.pumpWidget(_page([v]));
    expect(find.textContaining('balanserar inte'), findsOneWidget);
    expect(find.textContaining('Skillnad'), findsOneWidget);
  });

  testWidgets('says so when the period has no verifications', (tester) async {
    await tester.pumpWidget(_page(const []));
    expect(find.text('Inga verifikationer i perioden.'), findsOneWidget);
  });
}
