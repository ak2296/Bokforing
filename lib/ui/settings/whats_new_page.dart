import 'package:flutter/material.dart';

import '../../app/settings_keys.dart';
import '../../data/repository.dart';
import '../../domain/release_notes.dart';
import '../app_icons.dart';
import '../theme.dart';
import '../widgets/blur_overlay.dart';

/// The highest note the owner has seen (0 when none).
Future<int> notesSeen(Repository repo) async => int.tryParse(await repo.setting(SettingsKeys.notesSeen) ?? '') ?? 0;

Future<void> markNotesSeen(Repository repo) => repo.setSetting(SettingsKeys.notesSeen, '$latestNoteId');

/// After an update: the new notes once, as a sheet. Does nothing when the
/// owner has already seen the newest note.
Future<void> showWhatsNewIfNew(BuildContext context, Repository repo) async {
  final seen = await notesSeen(repo);
  if (seen >= latestNoteId || !context.mounted) return;
  // Let the app settle first: right after an install Android may restart the
  // app once more, and a sheet shown in that moment is gone before it is read.
  await Future<void>.delayed(const Duration(milliseconds: 900));
  if (!context.mounted) return;
  final shown = Stopwatch()..start();
  final note = releaseNotes.first;
  final all = await showBlurSheet<bool>(
    context: context,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppTheme.seed, borderRadius: BorderRadius.circular(11)),
            child: const Icon(AppIcons.news, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Nytt i Quee', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            Text(note.date, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ]),
        const SizedBox(height: 12),
        NoteItems(note.items.take(3).toList()),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stäng'))),
          const SizedBox(width: 8),
          Expanded(child: FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Visa alla nyheter'))),
        ]),
      ]),
    ),
  );
  // Only a sheet that stayed long enough to be read counts as seen; one that
  // vanished at once comes back next time.
  if (all != null || shown.elapsedMilliseconds > 2000) await markNotesSeen(repo);
  if (all == true && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WhatsNewPage()));
  }
}

/// A bulleted list of changes, each with a bold lead-in.
class NoteItems extends StatelessWidget {
  final List<(String, String)> items;
  const NoteItems(this.items, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (lead, rest) in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: Container(width: 5, height: 5, decoration: BoxDecoration(color: AppTheme.seed, shape: BoxShape.circle)),
            ),
            Expanded(
              child: Text.rich(TextSpan(children: [
                if (lead.isNotEmpty) TextSpan(text: '$lead ', style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: rest),
              ]), style: t.bodyMedium),
            ),
          ]),
        ),
    ]);
  }
}

/// Inställningar → Mer → Nyheter: every release, newest first.
class WhatsNewPage extends StatelessWidget {
  const WhatsNewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Nyheter')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          for (final (i, note) in releaseNotes.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(note.date, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                      if (i == 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                          decoration: BoxDecoration(color: AppTheme.pumpkin, borderRadius: BorderRadius.circular(20)),
                          child: Text('Ny', style: t.labelSmall?.copyWith(color: Colors.white)),
                        ),
                    ]),
                    Text(note.title, style: t.bodySmall),
                    const SizedBox(height: 10),
                    NoteItems(note.items),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
