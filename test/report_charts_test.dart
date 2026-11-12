import 'package:bokforing/domain/money.dart';
import 'package:bokforing/ui/widgets/report_charts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the calendar shows every day of the month, and a sales day by name', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SalesHeatMap(year: 2026, month: 10, byDay: {5: Money.kr(1000), 6: Money.kr(4000)}),
        ),
      ),
    ));
    for (final d in [1, 15, 31]) {
      expect(find.text('$d'), findsOneWidget);
    }
    expect(find.text('32'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('^6 okt: 4')), findsOneWidget);
    expect(find.bySemanticsLabel('7 okt: ingen försäljning'), findsOneWidget);
  });

  testWidgets('the result bars draw with a loss in the year', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SignedBarChart(labels: ['jan', 'feb', 'mar'], values: [1000, -500, 0], semanticLabel: 'Resultat'),
      ),
    ));
    expect(find.bySemanticsLabel('Resultat'), findsOneWidget);
  });
}
