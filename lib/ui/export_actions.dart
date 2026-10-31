import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../export/monthly_pdf.dart';
import 'widgets/common.dart';

String _fileName(MonthData m) {
  final r = m.report;
  return 'manadsrapport_${r.year}-${r.month.toString().padLeft(2, '0')}.pdf';
}

/// "Exportera PDF": the user picks where the file is saved (Android's
/// document picker). Nothing is uploaded anywhere.
Future<void> exportMonthlyPdf(BuildContext context, MonthData m) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await buildMonthlyPdf(m.report, m.profile);
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Spara månadsrapport',
      fileName: _fileName(m),
      bytes: bytes,
    );
    if (uri == null) return;
    messenger.showSnackBar(const SnackBar(content: Text('PDF-filen har sparats.')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('PDF-filen kunde inte sparas: $e')));
  }
}

/// "Skriv ut": Android's print dialog, which also offers "Spara som PDF".
Future<void> printMonthly(BuildContext context, MonthData m) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await Printing.layoutPdf(
      name: _fileName(m),
      onLayout: (_) => buildMonthlyPdf(m.report, m.profile),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Utskriften kunde inte startas: $e')));
  }
}
