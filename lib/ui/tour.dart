import 'package:flutter/material.dart';

import 'theme.dart';

/// One stop of the walkthrough: a part of the screen, lit up, with a short text.
class TourStep {
  final GlobalKey target;
  final String title;
  final String text;
  const TourStep(this.target, this.title, this.text);
}

/// A walkthrough: the screen is dimmed, one part is lit and a speech box says
/// what it is for. "Nästa" goes on, "Hoppa över" ends it.
class AppTour {
  const AppTour._();

  static void start(BuildContext context, List<TourStep> steps) {
    if (steps.isEmpty) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(builder: (_) => _TourOverlay(steps: steps, onClose: () => entry.remove()));
    overlay.insert(entry);
  }
}

class _TourOverlay extends StatefulWidget {
  final List<TourStep> steps;
  final VoidCallback onClose;
  const _TourOverlay({required this.steps, required this.onClose});

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> {
  int _i = 0;

  Rect? _rectOf(TourStep s) {
    final box = s.target.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_i];
    final rect = _rectOf(step);
    final size = MediaQuery.sizeOf(context);
    final last = _i == widget.steps.length - 1;
    final t = Theme.of(context).textTheme;
    final card = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.hairline),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(step.title, style: t.titleMedium),
          const SizedBox(height: 6),
          Text(step.text, style: t.bodyMedium),
          const SizedBox(height: 12),
          Row(children: [
            if (!last) TextButton(onPressed: widget.onClose, child: const Text('Hoppa över')),
            const Spacer(),
            Text('${_i + 1}/${widget.steps.length}', style: t.bodySmall),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => last ? widget.onClose() : setState(() => _i++),
              child: Text(last ? 'Klar' : 'Nästa'),
            ),
          ]),
        ]),
      ),
    );
    final above = rect != null && rect.center.dy >= size.height / 2;
    return Material(
      type: MaterialType.transparency,
      child: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: CustomPaint(painter: _DimPainter(rect)),
          ),
        ),
        if (rect == null)
          Center(child: Padding(padding: const EdgeInsets.all(16), child: card))
        else
          Positioned(
            left: 16,
            right: 16,
            top: above ? null : rect.bottom + 16,
            bottom: above ? size.height - rect.top + 16 : null,
            child: Align(alignment: Alignment.center, child: card),
          ),
      ]),
    );
  }
}

class _DimPainter extends CustomPainter {
  final Rect? hole;
  _DimPainter(this.hole);

  @override
  void paint(Canvas canvas, Size size) {
    final all = Path()..addRect(Offset.zero & size);
    if (hole == null) {
      canvas.drawPath(all, Paint()..color = Colors.black.withValues(alpha: 0.66));
      return;
    }
    final shape = RRect.fromRectAndRadius(hole!.inflate(6), const Radius.circular(20));
    canvas.drawPath(
        Path.combine(PathOperation.difference, all, Path()..addRRect(shape)), Paint()..color = Colors.black.withValues(alpha: 0.66));
    canvas.drawRRect(
        shape,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.hole != hole;
}
