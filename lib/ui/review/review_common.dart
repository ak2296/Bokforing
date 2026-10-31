import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../scan/scan_context.dart';
import '../theme.dart';

enum DuplicateChoice { showExisting, saveAnyway, cancel }

Future<DuplicateChoice> duplicateDialog(BuildContext context,
    {required String title, required List<String> lines}) async {
  final choice = await showDialog<DuplicateChoice>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Redan registrerat:'),
          const SizedBox(height: 6),
          for (final l in lines) Text('• $l'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, DuplicateChoice.cancel), child: const Text('Avbryt')),
        TextButton(onPressed: () => Navigator.pop(c, DuplicateChoice.showExisting), child: const Text('Visa befintlig')),
        FilledButton(onPressed: () => Navigator.pop(c, DuplicateChoice.saveAnyway), child: const Text('Registrera ändå')),
      ],
    ),
  );
  return choice ?? DuplicateChoice.cancel;
}

/// Confirms the save to the user and returns to the main screen.
void showSaved(BuildContext context) {
  final messenger = ScaffoldMessenger.of(context);
  Navigator.of(context).popUntil((r) => r.isFirst);
  messenger.showSnackBar(const SnackBar(content: Text('Registreringen har sparats.')));
}

class DocTypeHeader extends StatelessWidget {
  final String label;
  const DocTypeHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text('Dokumenttyp: $label', style: Theme.of(context).textTheme.titleMedium),
      );
}

class NoteCard extends StatelessWidget {
  final String text;
  const NoteCard(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Card(
        color: AppTheme.warning.withValues(alpha: 0.1),
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: const Icon(Icons.info_outline, color: AppTheme.warning),
          title: Text(text),
        ),
      );
}

/// Layout shared by the review screens: document preview, the form, and the
/// buttons "Godkänn och spara / Redigera / Skanna igen / Avbryt".
class ReviewScaffold extends StatelessWidget {
  final String title;
  final ScanContext? scan;
  final bool editing;
  final bool saving;
  final VoidCallback onSave;
  final VoidCallback onEdit;
  final VoidCallback? onRescan;
  final Widget child;

  const ReviewScaffold({
    super.key,
    required this.title,
    required this.scan,
    required this.editing,
    required this.saving,
    required this.onSave,
    required this.onEdit,
    required this.onRescan,
    required this.child,
  });

  Future<void> _cancel(BuildContext context) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Avbryt?'),
        content: const Text('Uppgifterna sparas inte.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Fortsätt granska')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Avbryt utan att spara')),
        ],
      ),
    );
    if (leave == true) {
      await scan?.discardImages();
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = scan;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel(context);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (s != null) _Preview(scan: s),
                    if (s == null || !editing)
                      const SizedBox.shrink()
                    else
                      const SizedBox(height: 4),
                    child,
                  ],
                ),
              ),
              Material(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        icon: saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check),
                        label: const Text('Godkänn och spara'),
                        onPressed: saving ? null : onSave,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                                onPressed: saving ? null : onEdit,
                                child: Text(editing ? 'Klar med ändringar' : 'Redigera')),
                          ),
                          if (onRescan != null)
                            Expanded(child: TextButton(onPressed: saving ? null : onRescan, child: const Text('Skanna igen'))),
                          Expanded(
                            child: TextButton(
                                onPressed: saving ? null : () => _cancel(context), child: const Text('Avbryt')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final ScanContext scan;
  const _Preview({required this.scan});

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 16),
        child: ExpansionTile(
          leading: const Icon(Icons.image_outlined),
          title: const Text('Skannat dokument'),
          subtitle: const Text('Tryck för att jämföra med bilden'),
          children: [
            for (final path in scan.imagePaths)
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Skannat dokument')),
                          body: InteractiveViewer(maxScale: 6, child: Center(child: Image.file(File(path)))),
                        ))),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: Image.file(File(path), fit: BoxFit.contain),
                ),
              ),
            ExpansionTile(
              title: const Text('Avläst text'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Kopiera avläst text'),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(ClipboardData(text: scan.ocrText));
                      messenger.showSnackBar(const SnackBar(content: Text('Texten är kopierad.')));
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(scan.ocrText, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      );
}
