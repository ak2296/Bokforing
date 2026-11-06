import 'dart:async';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../domain/models.dart';
import 'app_icons.dart';
import 'dashboard_page.dart';
import 'expenses_page.dart';
import 'reports/reports_page.dart';
import 'sales_page.dart';
import 'scan/scan_flow.dart';
import 'scan_tab.dart';
import 'settings/settings_page.dart';
import 'theme.dart';
import 'widgets/common.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  StreamSubscription<List<SharedMediaFile>>? _shares;

  static const _titles = ['Översikt', 'Försäljning', 'Skanna dokument', 'Utgifter', 'Rapporter'];

  void _go(int i) => setState(() => _index = i);

  @override
  void initState() {
    super.initState();
    // A PDF or image shared from another app, e.g. an e-mail attachment:
    // while the app is open, and the one that started the app.
    _shares = ReceiveSharingIntent.instance.getMediaStream().listen(_open);
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _open(files);
      ReceiveSharingIntent.instance.reset();
    });
  }

  @override
  void dispose() {
    _shares?.cancel();
    super.dispose();
  }

  void _open(List<SharedMediaFile> files) {
    if (files.isEmpty || !mounted) return;
    final f = files.first;
    readSharedFile(context, f.path, pdf: (f.mimeType ?? '').contains('pdf') || f.path.toLowerCase().endsWith('.pdf'));
  }

  @override
  Widget build(BuildContext context) {
    const pages = [
      DashboardPage(),
      SalesPage(),
      ScanTab(),
      ExpensesPage(),
      ReportsPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: _index == 0 ? const _CompanyTitle() : Text(_titles[_index]),
        actions: [
          IconButton(
            tooltip: 'Inställningar',
            icon: const Icon(AppIcons.settings),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(child: IndexedStack(index: _index, children: pages)),
      bottomNavigationBar: _BottomBar(index: _index, onTap: _go),
    );
  }
}

class _CompanyTitle extends StatelessWidget {
  const _CompanyTitle();

  @override
  Widget build(BuildContext context) => Reloading<BusinessProfile>(
        loader: (c) => c.repo.profile(),
        builder: (context, p) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(p.name.isEmpty ? 'Översikt' : p.name.toUpperCase()),
            Text(YearMonth.now().title, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomBar({required this.index, required this.onTap});

  static const _items = [
    ('Översikt', AppIcons.dashboard),
    ('Försäljning', AppIcons.register),
    ('Skanna', AppIcons.scan),
    ('Utgifter', AppIcons.expenses),
    ('Rapporter', AppIcons.report),
  ];

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: InkResponse(
                      onTap: () => onTap(i),
                      child: Semantics(
                        selected: i == index,
                        button: true,
                        // Every tab has the same icon and label layout, so the
                        // labels line up; the scan tab sits in a green tile.
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: i == 2
                                ? BoxDecoration(color: AppTheme.seed, borderRadius: BorderRadius.circular(14))
                                : null,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_items[i].$2,
                                    size: 22,
                                    color: i == 2 ? Colors.white : (i == index ? AppTheme.seed : AppTheme.muted)),
                                const SizedBox(height: 2),
                                Text(
                                  _items[i].$1,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: i == index || i == 2 ? FontWeight.w500 : FontWeight.w400,
                                    color: i == 2 ? Colors.white : (i == index ? AppTheme.seed : AppTheme.muted),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}
