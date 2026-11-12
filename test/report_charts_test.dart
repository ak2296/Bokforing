import 'package:bokforing/ui/widgets/report_charts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the result bars draw with a loss in the year', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SignedBarChart(labels: ['jan', 'feb', 'mar'], values: [1000, -500, 0], semanticLabel: 'Resultat'),
      ),
    ));
    expect(find.bySemanticsLabel('Resultat'), findsOneWidget);
  });
}
