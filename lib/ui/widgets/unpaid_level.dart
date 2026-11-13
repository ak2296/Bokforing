import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../notify/reminders.dart';
import '../theme.dart';
import '../unpaid_page.dart';

/// How urgent the unpaid invoices are: nothing special, inside the reminder
/// period the user chose in Inställningar (yellow), or overdue (red).
enum UnpaidLevel { none, normal, reminder, late }

class UnpaidInfo {
  final int count;
  final Money total;
  final int overdue;
  final UnpaidLevel level;
  const UnpaidInfo(this.count, this.total, this.overdue, this.level);

  /// [reminderDays] is null when the reminders are switched off.
  factory UnpaidInfo.of(List<Invoice> unpaid, int? reminderDays) {
    final days = [for (final i in unpaid) daysUntil(i.dueDate)];
    final overdue = days.where((d) => d != null && d < 0).length;
    final level = unpaid.isEmpty
        ? UnpaidLevel.none
        : overdue > 0
            ? UnpaidLevel.late
            : reminderDays != null && days.any((d) => d != null && d <= reminderDays)
                ? UnpaidLevel.reminder
                : UnpaidLevel.normal;
    return UnpaidInfo(unpaid.length, Money.sum(unpaid.map((i) => i.total)), overdue, level);
  }
}

/// The reminder period in days, or null when the reminders are off.
Future<int?> reminderWindow(Repository repo) async =>
    await Reminders.enabled(repo) ? await Reminders.days(repo) : null;

/// Fill, border and text colour for a card about unpaid invoices.
({Color fill, Color border, Color text}) unpaidColors(UnpaidLevel level) => switch (level) {
      UnpaidLevel.late => (fill: AppTheme.dangerTint, border: AppTheme.dangerBorder, text: AppTheme.danger),
      UnpaidLevel.reminder => (fill: AppTheme.warningTint, border: AppTheme.warningBorder, text: AppTheme.warning),
      _ => (fill: AppTheme.surface, border: AppTheme.hairline, text: AppTheme.ink),
    };
