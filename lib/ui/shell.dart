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

/// Bottom navigation with a spotlight over the chosen tab: a glowing lamp on
/// the top edge and a pumpkin light cone below it. Dark theme: a floating dark
/// pill. Light theme: a plain white bar.
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
  Widget build(BuildContext context) {
    final dark = AppTheme.dark;
    final bar = SizedBox(
      height: 64,
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: _Tab(
                label: _items[i].$1,
                icon: _items[i].$2,
                selected: i == index,
                scan: i == 2,
                dark: dark,
                onTap: () => onTap(i),
              ),
            ),
        ],
      ),
    );
    if (!dark) {
      return Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: AppTheme.hairline)),
        ),
        child: SafeArea(top: false, child: bar),
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0B100E),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppTheme.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: bar,
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool scan;
  final bool dark;
  final VoidCallback onTap;
  const _Tab(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.scan,
      required this.dark,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final onColor = scan ? Colors.white : (selected ? AppTheme.pumpkin : AppTheme.muted);
    return InkResponse(
      onTap: onTap,
      child: Semantics(
        selected: selected,
        button: true,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            // The light cone, widening from the lamp down over the tab.
            Positioned.fill(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: selected ? 1 : 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppTheme.pumpkin.withValues(alpha: dark ? 0.32 : 0.20),
                        AppTheme.pumpkin.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // The lamp.
            AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: selected ? 1 : 0,
              child: Container(
                width: 30,
                height: 3.5,
                decoration: BoxDecoration(
                  color: AppTheme.pumpkinLight,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
                  boxShadow: [BoxShadow(color: AppTheme.pumpkin.withValues(alpha: 0.85), blurRadius: dark ? 14 : 8, spreadRadius: 1)],
                ),
              ),
            ),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: scan ? BoxDecoration(color: AppTheme.seed, borderRadius: BorderRadius.circular(14)) : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 22, color: onColor),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: selected || scan ? FontWeight.w500 : FontWeight.w400,
                        color: onColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
