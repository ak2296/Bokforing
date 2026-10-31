import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'dashboard_page.dart';
import 'widgets/common.dart';

/// All registrations, newest first, with type, amount and status.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Historik')),
        body: Reloading<List<RegistrationSummary>>(
          loader: (c) => c.repo.recentRegistrations(limit: 1000),
          builder: (context, list) => list.isEmpty
              ? const EmptyState(icon: Icons.history, text: 'Inga registreringar ännu.')
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final e in list) RegistrationTile(entry: e, showStatus: true),
                  ],
                ),
        ),
      );
}
