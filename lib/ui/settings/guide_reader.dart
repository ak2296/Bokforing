
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../app_icons.dart';
import '../theme.dart';
import 'user_guide.dart';

/// A very simple in-app reader for the user guide: the pages of the phone PDF
/// as pictures, one under the other, with a contents list at the top that
/// scrolls to a chapter. Nothing else can act on the pages (no editing, no
/// pen), unlike a PDF opened in another app.
class GuideReaderPage extends StatefulWidget {
  const GuideReaderPage({super.key});

  @override
  State<GuideReaderPage> createState() => _GuideReaderPageState();
}

class _Shot {
  final Uint8List png;
  final int width;
  final int height;
  const _Shot(this.png, this.width, this.height);
}

class _GuideReaderPageState extends State<GuideReaderPage> {
  final _scroll = ScrollController();
  List<_Shot>? _pages;
  List<String> _titles = const [];
  Object? _error;

  static const _rowHeight = 56.0;
  static const _contentsHead = 76.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final pdf = (await rootBundle.load('assets/anvandarguide.pdf')).buffer.asUint8List();
      try {
        final text = await rootBundle.loadString('assets/anvandarguide_innehall.txt');
        _titles = [for (final l in text.split('\n')) if (l.trim().isNotEmpty) l.trim()];
      } catch (_) {
        _titles = const [];
      }
      final shots = <_Shot>[];
      await for (final r in Printing.raster(pdf, dpi: 220)) {
        shots.add(_Shot(await r.toPng(), r.width, r.height));
      }
      if (shots.isEmpty) throw StateError('Guiden har inga sidor.');
      if (mounted) setState(() => _pages = shots);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  double get _contentsHeight => _contentsHead + _titles.length * _rowHeight + 12;

  /// Where item [i] starts: the cover, the contents (the PDF's own contents
  /// page is replaced by tappable rows), then one page per chapter.
  double _offsetOf(int i, double width) {
    final pages = _pages!;
    var y = 0.0;
    for (var k = 0; k < i; k++) {
      y += k == 1 ? _contentsHeight : width * pages[k].height / pages[k].width;
    }
    return y;
  }

  void _jump(int item, double width) => _scroll.animateTo(
        _offsetOf(item, width).clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Användarguide'),
        actions: [
          if (pages != null && _titles.isNotEmpty)
            IconButton(
              tooltip: 'Innehåll',
              icon: const Icon(AppIcons.text),
              onPressed: () => _jump(1, MediaQuery.of(context).size.width),
            ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Guiden kunde inte visas här.', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => openUserGuide(context), child: const Text('Öppna i en annan app')),
                ]),
              ),
            )
          : pages == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, box) => ListView.builder(
                    controller: _scroll,
                    itemCount: pages.length,
                    itemBuilder: (context, i) {
                      if (i == 1 && _titles.isNotEmpty) return _contents(context, box.maxWidth);
                      if (i == 1) return _image(pages[i]);
                      return _image(pages[i]);
                    },
                  ),
                ),
    );
  }

  Widget _image(_Shot s) => AspectRatio(
        aspectRatio: s.width / s.height,
        child: Image.memory(s.png, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium),
      );

  Widget _contents(BuildContext context, double width) {
    final t = Theme.of(context).textTheme;
    return SizedBox(
      height: _contentsHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: _contentsHead - 18,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Det här finns i guiden', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            ),
          ),
          for (final (i, title) in _titles.indexed)
            SizedBox(
              height: _rowHeight,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                // Chapter i + 1 is the page after the cover and the contents.
                onTap: () => _jump(i + 2 < _pages!.length ? i + 2 : _pages!.length - 1, width),
                child: Row(children: [
                  SizedBox(width: 34, child: Text('${i + 1}', style: t.titleMedium?.copyWith(color: AppTheme.seed, fontWeight: FontWeight.w600))),
                  Expanded(child: Text(title, style: t.bodyLarge)),
                  Icon(AppIcons.chevronRight, size: 18, color: AppTheme.muted),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
