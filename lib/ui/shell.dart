import 'package:flutter/material.dart';

import 'dashboard_page.dart';
import 'expenses_page.dart';
import 'reports/reports_page.dart';
import 'sales_page.dart';
import 'scan_tab.dart';
import 'settings/settings_page.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  static const _titles = ['Översikt', 'Försäljning', 'Skanna dokument', 'Utgifter', 'Rapporter'];

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(onScan: () => _go(2)),
      const SalesPage(),
      const ScanTab(),
      const ExpensesPage(),
      const ReportsPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            tooltip: 'Inställningar',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: SafeArea(child: IndexedStack(index: _index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Översikt'),
          NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), label: 'Försäljning'),
          NavigationDestination(
              icon: CircleAvatar(radius: 20, child: Icon(Icons.document_scanner_outlined)),
              label: 'Skanna'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Utgifter'),
          NavigationDestination(icon: Icon(Icons.table_chart_outlined), label: 'Rapporter'),
        ],
      ),
    );
  }
}
