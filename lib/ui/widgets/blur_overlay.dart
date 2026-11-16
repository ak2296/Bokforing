import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// A box that opens on top of the page (a dialog or a sheet) blurs the page
/// below a little, so the eye goes to the box. These two replace showDialog and
/// showModalBottomSheet everywhere in the app.

final _blur = ImageFilter.blur(sigmaX: 5, sigmaY: 5);

/// Same as showDialog, with the page below blurred.
Future<T?> showBlurDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) =>
    showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      // The blur covers the whole screen, status bar and navigation bar too.
      useSafeArea: false,
      builder: (context) => Stack(fit: StackFit.expand, children: [
        Positioned.fill(child: IgnorePointer(child: BackdropFilter(filter: _blur, child: const SizedBox.expand()))),
        SafeArea(child: builder(context)),
      ]),
    );

/// Same as showModalBottomSheet (a drag handle, content as tall as it needs, up
/// to most of the screen, lifted above the keyboard), with the page below blurred.
Future<T?> showBlurSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = true,
  bool isScrollControlled = false,
}) =>
    showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, _, _) => _SheetFrame(showDragHandle: showDragHandle, child: builder(context)),
      transitionBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );

class _SheetFrame extends StatelessWidget {
  final bool showDragHandle;
  final Widget child;
  const _SheetFrame({required this.showDragHandle, required this.child});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    return Stack(fit: StackFit.expand, children: [
      // Blur and a tap outside the sheet closes it.
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: BackdropFilter(filter: _blur, child: const SizedBox.expand()),
        ),
      ),
      Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: media.size.height * 0.92, maxWidth: 640),
            child: Material(
              color: theme.bottomSheetTheme.backgroundColor ?? theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                top: false,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (showDragHandle)
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  Flexible(child: child),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
