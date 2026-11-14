import 'dart:async';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../app/app_controller.dart';
import '../app/settings_keys.dart';
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
import 'tour.dart';
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
  final _tabKeys = List.generate(5, (_) => GlobalKey());
  final _gearKey = GlobalKey();

  /// A tap on a tab makes a soft flash on the page, above the cards and under the bar.
  final _flash = ValueNotifier<_FlashEvent?>(null);
  AppController? _app;

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
    // The first start after the setup shows the walkthrough once.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final app = AppScope.read(context);
      // A look for a new version never blocks anything and fails quietly.
      unawaited(app.checkForUpdate());
      final repo = app.repo;
      if (await repo.boolSetting(SettingsKeys.tourPending) && mounted) {
        await repo.setBoolSetting(SettingsKeys.tourPending, false);
        _startTour();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = AppScope.read(context);
    if (!identical(c, _app)) {
      _app?.tourRequests.removeListener(_onTourRequest);
      _app = c..tourRequests.addListener(_onTourRequest);
    }
  }

  void _onTourRequest() => Future.delayed(const Duration(milliseconds: 450), _startTour);

  void _startTour() {
    if (!mounted) return;
    AppTour.start(context, [
      TourStep(_tabKeys[0], 'Översikt', 'Månadens siffror, kommande betalningar och sådant som behöver din uppmärksamhet samlas här.'),
      TourStep(_tabKeys[2], 'Börja här: Skanna',
          'Tryck Skanna och fotografera en faktura, ett kvitto, en Z-rapport eller ett lönebesked. Appen läser av det och du kontrollerar uppgifterna. Inget sparas förrän du godkänner.'),
      TourStep(_tabKeys[1], 'Försäljning', 'Dina Z-rapporter och din onlineförsäljning, dag för dag.'),
      TourStep(_tabKeys[3], 'Utgifter', 'Fakturor och kvitton, och vad som återstår att betala.'),
      TourStep(_tabKeys[4], 'Rapporter',
          'Månad, år, resultat och jämförelse. Här skickar du PDF, Excel eller SIE-fil till din redovisare.'),
      TourStep(_gearKey, 'Inställningar',
          'Slå på automatisk säkerhetskopia och PIN-kod här. Rundturen kan visas igen under Mer.'),
    ]);
  }

  @override
  void dispose() {
    _flash.dispose();
    _app?.tourRequests.removeListener(_onTourRequest);
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
      extendBody: true,
      appBar: AppBar(
        toolbarHeight: 64,
        title: _index == 0 ? const _CompanyTitle() : Text(_titles[_index]),
        actions: [
          IconButton(
            key: _gearKey,
            tooltip: 'Inställningar',
            icon: const Icon(AppIcons.settings),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Stack(children: [
          IndexedStack(
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
          Positioned.fill(child: IgnorePointer(child: _FlashLayer(events: _flash))),
        ]),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.background.withValues(alpha: 0), AppTheme.background.withValues(alpha: 0.92)],
          ),
        ),
        child: _BottomBar(
          index: _index,
          onTap: _go,
          keys: _tabKeys,
          onFlash: (at, color) => _flash.value = _FlashEvent(at, color),
        ),
      ),
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
/// from a short glowing stretch of the pill's top edge; its light is as wide as the lamp.
class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<GlobalKey> keys;
  final void Function(Offset at, Color color) onFlash;
  const _BottomBar({required this.index, required this.onTap, required this.keys, required this.onFlash});

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
          // The tap splash is painted on the nearest Material. Without one here that is the
          // page's, behind the cards, so the splash was hidden. This one sits on the pill.
          child: Material(
            type: MaterialType.transparency,
            child: Row(
              children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: KeyedSubtree(
                      key: keys[i],
                      child: _Tab(
                        label: _items[i].$1,
                        icon: _items[i].$2,
                        selected: i == index,
                        scan: i == 2,
                        dark: dark,
                        onTap: () => onTap(i),
                      onFlash: onFlash,
                      ),
                    ),
                  ),
              ],
            ),
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
  final void Function(Offset at, Color color) onFlash;
  const _Tab(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.scan,
      required this.dark,
      required this.onTap,
      required this.onFlash});

  @override
  Widget build(BuildContext context) {
    final idle = scan ? AppTheme.seed : AppTheme.muted;
    final color = selected ? AppTheme.pumpkin : idle;
    final light = scan ? const Color(0xFF2FD08F) : AppTheme.pumpkin;
    return InkResponse(
      onTap: onTap,
      onTapDown: (d) => onFlash(d.globalPosition, light),
      // The feedback is the flash on the page; no splash on the pill or behind the cards.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
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

/// The lamp is a short glowing stretch of the pill's top edge. The light it
/// casts is exactly as wide as the lamp where it starts, widens only a little
/// (enough to light the label) and fades out quickly.
class _ConePainter extends CustomPainter {
  static const lampWidth = 34.0;
  final Color color;
  final bool dark;
  _ConePainter(this.color, this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    const top = lampWidth / 2;
    final bottom = top + 13;
    final reach = size.height * 0.72;
    final path = Path()
      ..moveTo(cx - top, 0)
      ..lineTo(cx + top, 0)
      ..lineTo(cx + bottom, reach)
      ..lineTo(cx - bottom, reach)
      ..close();
    final cone = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: dark ? 0.6 : 0.42),
          color.withValues(alpha: dark ? 0.18 : 0.12),
          color.withValues(alpha: 0),
        ],
        stops: const [0, 0.45, 1],
      ).createShader(Rect.fromLTWH(0, 0, size.width, reach))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawPath(path, cone);
    final lamp = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - top, 0, lampWidth, 2.5), const Radius.circular(2));
    canvas.drawRRect(
        lamp, Paint()..color = color.withValues(alpha: 0.9)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawRRect(lamp, Paint()..color = Color.lerp(color, Colors.white, 0.35)!);
  }

  @override
  bool shouldRepaint(_ConePainter old) => old.color != color || old.dark != dark;
}

class _FlashEvent {
  final Offset global;
  final Color color;
  const _FlashEvent(this.global, this.color);
}

/// A soft round flash that opens where a tab was tapped and fades out. It is
/// drawn over the page, so it shows on top of cards, and under the bar.
class _FlashLayer extends StatefulWidget {
  final ValueNotifier<_FlashEvent?> events;
  const _FlashLayer({required this.events});

  @override
  State<_FlashLayer> createState() => _FlashLayerState();
}

class _FlashLayerState extends State<_FlashLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  Offset? _at;
  Color _color = Colors.transparent;

  @override
  void initState() {
    super.initState();
    widget.events.addListener(_start);
  }

  void _start() {
    final e = widget.events.value;
    final box = context.findRenderObject();
    if (e == null || box is! RenderBox || !box.attached) return;
    _at = box.globalToLocal(e.global);
    _color = e.color;
    _anim.forward(from: 0);
  }

  @override
  void dispose() {
    widget.events.removeListener(_start);
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _anim,
        builder: (context, _) => CustomPaint(painter: _FlashPainter(_at, _color, _anim.value)),
      );
}

class _FlashPainter extends CustomPainter {
  final Offset? at;
  final Color color;
  final double t;
  const _FlashPainter(this.at, this.color, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = at;
    if (c == null || t <= 0 || t >= 1) return;
    final r = 30 + 90 * Curves.easeOut.transform(t);
    final a = (1 - t) * 0.34;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: a), color.withValues(alpha: a * 0.6), color.withValues(alpha: 0)],
          stops: const [0, 0.6, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_FlashPainter old) => old.at != at || old.color != color || old.t != t;
}
