import 'package:flutter/material.dart';

import '../../domain/dates.dart';
import '../../domain/money.dart';
import '../app_icons.dart';
import '../theme.dart';

/// The big figure at the top of Försäljning and Utgifter: a coloured card
/// with the month's total and a few key numbers below it.
class SummaryHero extends StatelessWidget {
  final String label;
  final Money total;
  final List<(String, String)> stats;
  final Color color;
  final IconData icon;
  const SummaryHero({
    super.key,
    required this.label,
    required this.total,
    required this.stats,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const onColor = Colors.white;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.28)!],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: onColor.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 17, color: onColor),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: t.bodyMedium?.copyWith(color: onColor.withValues(alpha: 0.85)))),
        ]),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(total.format(),
              style: t.headlineMedium?.merge(moneyStyle).copyWith(color: onColor, fontSize: 30, fontWeight: FontWeight.w600)),
        ),
        if (stats.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(height: 1, color: onColor.withValues(alpha: 0.18)),
          const SizedBox(height: 12),
          Row(children: [
            for (final (i, s) in stats.indexed) ...[
              if (i > 0) Container(width: 1, height: 30, color: onColor.withValues(alpha: 0.18)),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.$1, style: t.bodySmall?.copyWith(color: onColor.withValues(alpha: 0.75))),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(s.$2, style: t.titleSmall?.merge(moneyStyle).copyWith(color: onColor)),
                    ),
                  ]),
                ),
              ),
            ],
          ]),
        ],
      ]),
    );
  }
}

/// Month navigation as a white pill: ‹ Oktober 2026 ›.
class MonthPill extends StatelessWidget {
  final String title;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  const MonthPill({super.key, required this.title, required this.onPrevious, required this.onNext});

  @override
  Widget build(BuildContext context) => Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppTheme.hairline),
        ),
        child: Row(children: [
          IconButton(
              tooltip: 'Föregående månad',
              visualDensity: VisualDensity.compact,
              icon: const Icon(AppIcons.chevronLeft, size: 20),
              onPressed: onPrevious),
          Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(AppIcons.calendar, size: 16, color: AppTheme.muted),
              const SizedBox(width: 6),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
            ]),
          ),
          IconButton(
              tooltip: 'Nästa månad',
              visualDensity: VisualDensity.compact,
              icon: const Icon(AppIcons.chevronRight, size: 20),
              onPressed: onNext),
        ]),
      );
}

/// A section heading with an optional count on the right.
class SectionTitle extends StatelessWidget {
  final String text;
  final String? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(children: [
        Expanded(child: Text(text, style: t.titleMedium)),
        if (trailing != null) Text(trailing!, style: t.bodySmall),
      ]),
    );
  }
}

/// Day number over a short weekday, in a rounded tile: "05 / tis".
class DateBadge extends StatelessWidget {
  final String isoDate;
  final Color? background;
  final Color? color;
  const DateBadge(this.isoDate, {super.key, this.background, this.color});

  static const _weekdays = ['mån', 'tis', 'ons', 'tor', 'fre', 'lör', 'sön'];

  @override
  Widget build(BuildContext context) {
    final d = SwedishDates.parseIso(isoDate);
    final color = this.color ?? AppTheme.seed;
    return Container(
      width: 44,
      height: 46,
      decoration: BoxDecoration(color: background ?? AppTheme.tint, borderRadius: BorderRadius.circular(13)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(d == null ? '–' : d.day.toString().padLeft(2, '0'),
            style: TextStyle(fontSize: 16, height: 1.1, fontWeight: FontWeight.w600, color: color)),
        Text(d == null ? '' : _weekdays[d.weekday - 1],
            style: TextStyle(fontSize: 11, height: 1.2, color: color.withValues(alpha: 0.8))),
      ]),
    );
  }
}

/// A small coloured label: "Obetald", "Skillnad", "Online".
class StatusChip extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;
  const StatusChip(this.text, {super.key, this.color = AppTheme.warning, this.background = AppTheme.warningTint});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color)),
      );
}

/// One row in a [LedgerCard]: date badge, title, details, amount.
class LedgerRow extends StatelessWidget {
  final String isoDate;
  final String title;
  final String subtitle;
  final Money amount;
  final List<Widget> chips;
  final VoidCallback onTap;
  final Color? badgeBackground;
  final Color? badgeColor;
  const LedgerRow({
    super.key,
    required this.isoDate,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.onTap,
    this.chips = const [],
    this.badgeBackground,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(children: [
          DateBadge(isoDate, background: badgeBackground, color: badgeColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
              const SizedBox(height: 2),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 5),
                Wrap(spacing: 6, runSpacing: 4, children: chips),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          Text(amount.format(compact: true),
              style: t.titleSmall?.merge(moneyStyle).copyWith(color: amount.isNegative ? AppTheme.seed : null)),
        ]),
      ),
    );
  }
}

/// White rounded card holding rows with thin dividers between them.
class LedgerCard extends StatelessWidget {
  final List<Widget> children;
  const LedgerCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const Divider(indent: 70),
            c,
          ],
        ]),
      );
}

/// Shares as one stacked bar with a legend: where the money went or came from.
class ShareBar extends StatelessWidget {
  final List<(String, Money)> parts;
  final List<Color> colors;
  const ShareBar({super.key, required this.parts, required this.colors});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final positive = parts.where((p) => p.$2.ore > 0).toList();
    final total = positive.fold<int>(0, (n, p) => n + p.$2.ore);
    if (total <= 0) return const SizedBox.shrink();
    Color colorAt(int i) => colors[i % colors.length];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 12,
              child: Row(children: [
                for (final (i, p) in positive.indexed) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(flex: (p.$2.ore * 1000 ~/ total).clamp(1, 1000), child: Container(color: colorAt(i))),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 12),
          for (final (i, p) in positive.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: colorAt(i), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(p.$1, style: t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text('${(p.$2.ore * 100 / total).round()} %', style: t.bodySmall),
                const SizedBox(width: 10),
                SizedBox(
                  width: 92,
                  child: Text(p.$2.format(compact: true), textAlign: TextAlign.right, style: moneyStyle),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Greens for sales, warm tones for costs. Neighbours alternate dark and
/// light, and the bar keeps a small gap between them, so each part is easy
/// to tell apart.
const salesPalette = [Color(0xFF0B6B4E), Color(0xFFB9DFCC), Color(0xFF3E9B7A), Color(0xFF9AA9A2), Color(0xFF5B7F72), Color(0xFF7CC4A6)];
const costPalette = [AppTheme.pumpkin, AppTheme.pumpkinPale, Color(0xFF8A5300), Color(0xFFD9A066), AppTheme.pumpkinLight, Color(0xFFB0A08A)];
