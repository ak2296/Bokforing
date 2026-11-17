import 'package:bokforing/ui/widgets/ledger_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dated rows are grouped in one card per week, newest week open', (tester) async {
    final entries = <(String, Widget)>[
      ('2026-11-13', const Text('fredag')),
      ('2026-11-10', const Text('tisdag')),
      ('2026-11-03', const Text('förra veckan')),
      ('2026-10-30', const Text('veckan innan')),
    ];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: weekCards(entries, color: Colors.orange)))));
    expect(find.text('Vecka 46'), findsOneWidget);
    expect(find.text('Vecka 45'), findsOneWidget);
    expect(find.text('Vecka 44'), findsOneWidget);
    expect(find.textContaining('· 2 st'), findsOneWidget);
    expect(find.textContaining('· 1 st'), findsNWidgets(2));
    // The newest week is open, the older ones are folded.
    expect(find.text('fredag'), findsOneWidget);
    expect(find.text('tisdag'), findsOneWidget);
    expect(find.text('förra veckan'), findsNothing);
    await tester.tap(find.text('Vecka 45'));
    await tester.pumpAndSettle();
    expect(find.text('förra veckan'), findsOneWidget);
  });

  testWidgets('no rows gives no cards', (tester) async {
    expect(weekCards(const [], color: Colors.orange), isEmpty);
  });
}
