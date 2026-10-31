import 'package:flutter/material.dart';

/// Entry point for scanning and manual entry. Camera, OCR and the review
/// screen are added in the next phase.
class ScanTab extends StatelessWidget {
  const ScanTab({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Card(
            child: ListTile(
              leading: Icon(Icons.construction_outlined),
              title: Text('Skanning och manuell registrering'),
              subtitle: Text('Den här delen byggs i nästa steg. Kategorier, inställningar och rapporter fungerar redan.'),
            ),
          ),
        ],
      );
}
