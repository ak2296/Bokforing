import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../domain/models.dart';
import '../export/monthly_pdf.dart';
import '../export/table_export.dart';
import 'app_icons.dart';
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

/// "Excel": the report as a CSV file that Excel and Google Sheets open.
Future<void> exportTableCsv(BuildContext context, ReportTable t) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final uri = await FilePicker.saveFile(dialogTitle: 'Spara för Excel', fileName: '${t.fileName}.csv', bytes: t.toCsv());
    if (uri == null) return;
    messenger.showSnackBar(const SnackBar(content: Text('Filen har sparats. Öppna den i Excel.')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Filen kunde inte sparas: $e')));
  }
}

Future<void> exportTablePdf(BuildContext context, ReportTable t, BusinessProfile profile) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final uri = await FilePicker.saveFile(
        dialogTitle: 'Spara rapport', fileName: '${t.fileName}.pdf', bytes: await t.toPdf(profile));
    if (uri == null) return;
    messenger.showSnackBar(const SnackBar(content: Text('PDF-filen har sparats.')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('PDF-filen kunde inte sparas: $e')));
  }
}

Future<void> printTable(BuildContext context, ReportTable t, BusinessProfile profile) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await Printing.layoutPdf(name: '${t.fileName}.pdf', onLayout: (_) => t.toPdf(profile));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Utskriften kunde inte startas: $e')));
  }
}

/// PDF, Excel and print for a report, side by side.
class ExportButtons extends StatelessWidget {
  final VoidCallback onPdf;
  final VoidCallback onExcel;
  final VoidCallback onPrint;
  const ExportButtons({super.key, required this.onPdf, required this.onExcel, required this.onPrint});

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
            icon: Icon(icon, size: 18),
            label: Text(label),
            onPressed: onTap,
          ),
        );
    return Row(children: [
      button(AppIcons.pdf, 'PDF', onPdf),
      const SizedBox(width: 8),
      button(AppIcons.table, 'Excel', onExcel),
      const SizedBox(width: 8),
      button(AppIcons.print, 'Skriv ut', onPrint),
    ]);
  }
}
