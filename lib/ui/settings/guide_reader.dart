import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_icons.dart';
import '../theme.dart';

/// A very simple in-app reader for the user guide: the guide's pages as picture
/// slices (made on the PC by make_guide_bilder.py), one under the other, with a
/// contents list at the top that scrolls to a chapter. The slices are plain
/// pictures, so nothing is rendered on the phone, only the slices near the screen
/// are loaded, and nothing can act on the pages (no editing, no pen).
class GuideReaderPage extends StatefulWidget {
  const GuideReaderPage({super.key});

  @override
  State<GuideReaderPage> createState() => _GuideReaderPageState();
}

class _Slice {
  final String file;
  final int height;
  final int page;
  const _Slice(this.file, this.height, this.page);
}

class _GuideReaderPageState extends State<GuideReaderPage> {
  static const _rowHeight = 56.0;
  static const _contentsHead = 76.0;
  static const _dir = 'assets/guide/';

  final _scroll = ScrollController();
  List<_Slice> _slices = const [];
  int _sliceWidth = 900;
  List<String> _titles = const [];
  Object? _error;
  bool _loaded = false;

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
      final index = jsonDecode(await rootBundle.loadString('${_dir}index.json')) as Map<String, dynamic>;
      final slices = <_Slice>[];
      final pages = index['pages'] as List;
      for (var p = 0; p < pages.length; p++) {
        for (final t in pages[p] as List) {
          slices.add(_Slice(t['f'] as String, t['h'] as int, p));
        }
      }
      if (slices.isEmpty) throw StateError('Guiden har inga sidor.');
      try {
        final text = await rootBundle.loadString('assets/anvandarguide_innehall.txt');
        _titles = [for (final l in text.split('\n')) if (l.trim().isNotEmpty) l.trim()];
      } catch (_) {
        _titles = const [];
      }
      if (mounted) {
        setState(() {
          _slices = slices;
          _sliceWidth = index['width'] as int;
          _loaded = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// The PDF's own contents page (page 1) is replaced by tappable rows.
  bool get _hasContents => _titles.isNotEmpty;

  /// What is shown, top to bottom: a slice, or null for the contents list.
  List<_Slice?> get _items {
    final out = <_Slice?>[];
    var contentsAdded = false;
    for (final s in _slices) {
      if (_hasContents && s.page == 1) {
        if (!contentsAdded) out.add(null);
        contentsAdded = true;
      } else {
        out.add(s);
      }
    }
    return out;
  }

  double get _contentsHeight => _contentsHead + _titles.length * _rowHeight + 12;

  double _heightOf(_Slice? s, double width) => s == null ? _contentsHeight : width * s.height / _sliceWidth;

  /// Where page [page] starts.
  double _offsetOfPage(int page, double width) {
    var y = 0.0;
    for (final s in _items) {
      if (s != null && s.page >= page) break;
      if (s == null && page <= 1) break;
      y += _heightOf(s, width);
    }
    return y;
  }

  void _jump(int page, double width) => _scroll.animateTo(
        _offsetOfPage(page, width).clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Användarguide'),
        actions: [
          if (_loaded && _hasContents)
            IconButton(
              tooltip: 'Innehåll',
              icon: const Icon(AppIcons.text),
              onPressed: () => _jump(1, MediaQuery.of(context).size.width),
            ),
        ],
      ),
      body: _error != null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Guiden kunde inte visas.', textAlign: TextAlign.center),
              ),
            )
          : !_loaded
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(builder: (context, box) {
                  final items = _items;
                  final px = MediaQuery.of(context).devicePixelRatio;
                  return ListView.builder(
                    controller: _scroll,
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final s = items[i];
                      if (s == null) return _contents(context, box.maxWidth);
                      return SizedBox(
                        height: _heightOf(s, box.maxWidth),
                        child: Image.asset(
                          '$_dir${s.file}',
                          width: box.maxWidth,
                          fit: BoxFit.fill,
                          cacheWidth: (box.maxWidth * px).round().clamp(1, _sliceWidth),
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                        ),
                      );
                    },
                  );
                }),
    );
  }

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
                onTap: () => _jump(i + 2, width),
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
