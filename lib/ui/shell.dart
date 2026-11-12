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
  /// The tab chosen in the bar: 0 Översikt, 1 Försäljning, 2 Skanna,
  /// 3 Utgifter, 4 Rapporter.
  int _index = 0;
  StreamSubscription<List<SharedMediaFile>>? _shares;

  /// Swiping moves between these four; Skanna is only opened from the bar.
  static const _swipeTabs = [0, 1, 3, 4];
  static const _scanTab = 2;
  final _pages = PageController();

  static const _titles = ['Översikt', 'Försäljning', 'Skanna dokument', 'Utgifter', 'Rapporter'];

  void _go(int i) {
    if (i == _scanTab) {
      setState(() => _index = i);
      return;
    }
    final page = _swipeTabs.indexOf(i);
    final fromScan = _index == _scanTab;
    setState(() => _index = i);
    if (!_pages.hasClients) return;
    final current = (_pages.page ?? 0).round();
    if (fromScan || (current - page).abs() > 1) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(page, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    }
  }

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
    _pages.dispose();
    super.dispose();
  }

  void _open(List<SharedMediaFile> files) {
    if (files.isEmpty || !mounted) return;
    final f = files.first;
    readSharedFile(context, f.path, pdf: (f.mimeType ?? '').contains('pdf') || f.path.toLowerCase().endsWith('.pdf'));
  }

  @override
  Widget build(BuildContext context) {
    const swipePages = [
      DashboardPage(),
      SalesPage(),
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
      body: SafeArea(
        child: IndexedStack(
          index: _index == _scanTab ? 1 : 0,
          children: [
            PageView(
              controller: _pages,
              onPageChanged: (p) {
                if (_index != _scanTab) setState(() => _index = _swipeTabs[p]);
              },
              children: [for (final p in swipePages) _KeepAlive(child: p)],
            ),
            const ScanTab(),
          ],
        ),
      ),
      bottomNavigationBar: _BottomBar(index: _index, onTap: _go),
    );
  }
}

/// Keeps a page and its state (chosen month, scroll) while it is swiped away.
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
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

/// Bottom navigation: a floating pill, the same in both themes (white in the
/// light theme, dark in the dark theme). The chosen tab is lit by a spotlight
/// above the pill's edge: only the cone of light that falls on the tab is seen.
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF0B100E) : AppTheme.surface,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppTheme.hairline),
            boxShadow: dark ? null : const [BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, 4))],
          ),
          clipBehavior: Clip.antiAlias,
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
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;

  /// Skanna: green when idle, pumpkin text under a green light when chosen.
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
    final idle = scan ? AppTheme.seed : AppTheme.muted;
    final color = selected ? AppTheme.pumpkin : idle;
    final light = scan ? const Color(0xFF2FD08F) : AppTheme.pumpkin;
    return InkResponse(
      onTap: onTap,
      child: Semantics(
        selected: selected,
        button: true,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: selected ? 1 : 0,
                child: CustomPaint(painter: _ConePainter(light, dark)),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 22, color: color),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: selected || scan ? FontWeight.w500 : FontWeight.w400,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A cone of light from a point at the top edge, widening downwards and fading
/// out. The lamp itself is outside the pill, so only the cast light is drawn.
class _ConePainter extends CustomPainter {
  final Color color;
  final bool dark;
  _ConePainter(this.color, this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final reach = size.width * 0.7;
    final path = Path()
      ..moveTo(cx - 7, 0)
      ..lineTo(cx + 7, 0)
      ..lineTo(cx + reach, size.height)
      ..lineTo(cx - reach, size.height)
      ..close();
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: dark ? 0.75 : 0.5), color.withValues(alpha: 0)],
      ).createShader(Offset.zero & size)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ConePainter old) => old.color != color || old.dark != dark;
}
