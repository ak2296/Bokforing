import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'domain/classifier.dart';
import 'domain/invoice_extractor.dart';
import 'domain/money.dart';
import 'domain/patterns.dart';
import 'domain/validation.dart';
import 'domain/z_extractor.dart';
import 'samples.dart';
import 'ui/scan_page.dart';

void main() => runApp(const BokforingApp());

class BokforingApp extends StatelessWidget {
  const BokforingApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Bokföringsassistent',
        debugShowCheckedModeBanner: false,
        locale: const Locale('sv', 'SE'),
        supportedLocales: const [Locale('sv', 'SE')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF0F5B4B)),
        home: const Shell(),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 2;
  static const _tabs = [
    ('Översikt', Icons.dashboard_outlined),
    ('Försäljning', Icons.point_of_sale),
    ('Skanna', Icons.document_scanner_outlined),
    ('Utgifter', Icons.receipt_long_outlined),
    ('Rapporter', Icons.table_chart_outlined),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_tabs[_i].$1),
          actions: [
            IconButton(
              tooltip: 'Inställningar',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Inställningar')),
                      body: const Center(
                          child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('Inställningar byggs i nästa fas.')))))),
            ),
          ],
        ),
        body: _i == 2
            ? const AnalyzePage()
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('${_tabs[_i].$1} byggs i nästa fas.',
                      textAlign: TextAlign.center),
                ),
              ),
        bottomNavigationBar: NavigationBarTheme(
          data: NavigationBarThemeData(
              labelTextStyle:
                  WidgetStateProperty.all(const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
          child: NavigationBar(
          selectedIndex: _i,
          onDestinationSelected: (v) => setState(() => _i = v),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            for (final t in _tabs) NavigationDestination(icon: Icon(t.$2), label: t.$1),
          ],
        ),
        ),
      );
}

/// Phase 1: paste document text and run the real classifier and extractors.
/// Camera and OCR replace the text box in phase 2 and 3.
class AnalyzePage extends StatefulWidget {
  const AnalyzePage({super.key});
  @override
  State<AnalyzePage> createState() => _AnalyzePageState();
}

class _AnalyzePageState extends State<AnalyzePage> {
  final _c = TextEditingController();
  String _text = '';
  DocumentType? _forced;
  String? _imagePath;
  final Map<int, String> _assign = {};

  Future<void> _scan() async {
    final r = await Navigator.of(context)
        .push<ScanResult>(MaterialPageRoute(builder: (_) => const ScanPage()));
    if (r == null || !mounted) return;
    setState(() {
      _c.text = r.text;
      _text = r.text;
      _forced = null;
      _assign.clear();
      _imagePath = r.imagePath;
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _example(String s) => setState(() {
        _c.text = s;
        _text = s;
        _forced = null;
        _assign.clear();
      });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      FilledButton.icon(
        onPressed: _scan,
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Skanna dokument'),
      ),
      const SizedBox(height: 8),
      if (_imagePath != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              Image.file(File(_imagePath!), height: 180, fit: BoxFit.contain),
              const Text('Skannad bild'),
            ]),
          ),
        ),
      const Text('Långa dokument: tryck på "Långt dokument" i kameran och ta en bild i taget. '
          'Texten från kameran kan innehålla fel. Du kan rätta texten nedan '
          'och trycka på Analysera igen. Du kan också klistra in text.'),
      const SizedBox(height: 8),
      TextField(
        controller: _c,
        minLines: 6,
        maxLines: 12,
        decoration: const InputDecoration(
            border: OutlineInputBorder(), labelText: 'Dokumentets text'),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton(
            onPressed: () => setState(() {
                  _text = _c.text;
                  _forced = null;
                  _assign.clear();
                }),
            child: const Text('Analysera')),
        OutlinedButton(onPressed: () => _example(sampleInvoice), child: const Text('Exempel: faktura')),
        OutlinedButton(onPressed: () => _example(sampleChangeReceipt), child: const Text('Exempel: kvitto med växel')),
        OutlinedButton(onPressed: () => _example(sampleMultiVat), child: const Text('Exempel: flera momssatser')),
        OutlinedButton(onPressed: () => _example(sampleZReport), child: const Text('Exempel: Z-rapport')),
      ]),
      const SizedBox(height: 16),
    ];
    if (_text.trim().length >= 20) children.addAll(_result(context));
    return ListView(padding: const EdgeInsets.all(16), children: children);
  }

  List<Widget> _result(BuildContext context) {
    final cls = classify(_text);
    final type = _forced ?? (cls.isCertain ? cls.type : null);
    if (type == null) {
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Vi är osäkra på dokumenttypen.'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                FilledButton(onPressed: () => setState(() => _forced = DocumentType.invoice), child: const Text('Faktura')),
                FilledButton(onPressed: () => setState(() => _forced = DocumentType.zReport), child: const Text('Z-rapport')),
                OutlinedButton(onPressed: () => setState(() => _text = ''), child: const Text('Annat')),
              ]),
            ]),
          ),
        ),
      ];
    }
    return type == DocumentType.invoice ? _invoice(cls) : _z(cls);
  }

  Widget _row(String k, String? v, [Confidence? c]) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 4, child: Text(k)),
          Expanded(flex: 5, child: Text(v ?? '–', style: const TextStyle(fontWeight: FontWeight.w600))),
          if (c != null) _badge(c),
        ]),
      );

  Widget _badge(Confidence c) => Text(
        switch (c) {
          Confidence.high => ' ✓',
          Confidence.medium => ' ⚠',
          Confidence.low => ' ⚠⚠',
          Confidence.manual => '',
        },
        style: TextStyle(
            color: c == Confidence.high ? Colors.green.shade700 : Colors.orange.shade800),
      );

  Widget _msg(ValidationResult r) {
    final ok = r.status == ValidationStatus.ok;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: ok ? Colors.green.shade50 : Colors.orange.shade50,
          borderRadius: BorderRadius.circular(6)),
      child: Text(r.message, style: TextStyle(color: ok ? Colors.green.shade900 : Colors.orange.shade900)),
    );
  }

  List<Widget> _invoice(Classification cls) {
    final r = extractInvoice(_text);
    final checks = <ValidationResult>[
      if (r.net != null && r.vatTotal != null && r.total != null)
        AccountingValidationEngine.checkInvoiceArithmetic(r.net!, r.vatTotal!, r.total!),
      if (r.vatLines.isNotEmpty && r.vatTotal != null)
        AccountingValidationEngine.checkVatBreakdown(r.vatLines.map((x) => x.vat), r.vatTotal!),
      for (final v in r.vatLines)
        if (v.net != null) AccountingValidationEngine.checkVatLine(v.ratePercent, v.net!, v.vat),
      if (r.vatTotal != null && r.total != null)
        AccountingValidationEngine.checkVatPlausible(r.vatTotal!, r.total!),
    ];
    return [
      Text('Kontrollera uppgifterna', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            _row('Dokumenttyp', 'Faktura${_forced == null ? ' (${(cls.confidence * 100).round()} %)' : ''}'),
            _row('Datum', r.date, r.dateConfidence),
            _row('Leverantör', r.supplier),
            _row('Fakturanummer', r.invoiceNumber),
            _row('Förfallodatum', r.dueDate),
            _row('OCR/referens', r.ocrReference),
            _row('Summa', r.total?.format(), r.totalConfidence),
            _row('Moms', r.vatTotal?.format(), r.vatConfidence),
            for (final v in r.vatLines)
              _row('  Moms ${v.ratePercent} %${v.net == null ? '' : '\n  (underlag ${v.net!.format()})'}',
                  v.vat.format()),
            if (r.candidates.length > 1)
              _row('Andra möjliga summor',
                  r.candidates.where((c) => c.value != r.total).map((c) => c.value.format()).join(', ')),
          ]),
        ),
      ),
      for (final c in checks) _msg(c),
      const SizedBox(height: 8),
      const Text('Redigering och sparande kommer i fas 7.'),
    ];
  }

  List<Widget> _z(Classification cls) {
    final r = extractZReport(_text, restaurantSuggestions);
    String catName(String id) {
      for (final c in restaurantSuggestions) {
        if (c.id == id) return c.name;
      }
      return '';
    }

    String eff(int i) => _assign[i] ?? r.lines[i].categoryId;
    final assigned = <Money>[
      for (var i = 0; i < r.lines.length; i++)
        if (eff(i).isNotEmpty && eff(i) != 'x') r.lines[i].amount
    ];
    final open = [
      for (var i = 0; i < r.lines.length; i++)
        if (eff(i).isEmpty) i
    ];
    final v = AccountingValidationEngine.reconcileZReport(assigned, r.total);
    return [
      Text('Kontrollera uppgifterna', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            _row('Dokumenttyp', 'Z-rapport${_forced == null ? ' (${(cls.confidence * 100).round()} %)' : ''}'),
            _row('Datum', r.date, r.dateConfidence),
            _row('Z-nummer', r.zNumber),
            _row('Dagsförsäljning', r.total?.format(), r.totalConfidence),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Text(
          r.sectionFound
              ? 'Rader från "Försäljning per varugrupp". Välj kategori för varje rad.'
              : 'Hittade ingen sektion "Försäljning per varugrupp". Alla rader med belopp visas, '
                  'välj kategori eller Ignorera.',
          style: Theme.of(context).textTheme.bodySmall),
      for (var i = 0; i < r.lines.length; i++)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(r.lines[i].label, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(r.lines[i].amount.format(), style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
              if (r.lines[i].suggestedId.isNotEmpty && eff(i).isEmpty)
                Text('Vi hittade en möjlig matchning: ${catName(r.lines[i].suggestedId)}',
                    style: TextStyle(color: Colors.orange.shade900)),
              DropdownButton<String>(
                isExpanded: true,
                value: eff(i),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Välj kategori')),
                  for (final c in restaurantSuggestions)
                    DropdownMenuItem(value: c.id, child: Text('${c.name} (${c.vatRatePercent} %)')),
                  const DropdownMenuItem(value: 'x', child: Text('Ignorera raden')),
                ],
                onChanged: (x) => setState(() => _assign[i] = x ?? ''),
              ),
            ]),
          ),
        ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            _row('Beräknad detaljerad summa', Money.sum(assigned).format()),
            _row('Dagsförsäljning', r.total?.format()),
            _row('Skillnad', r.total == null ? null : (Money.sum(assigned) - r.total!).format()),
          ]),
        ),
      ),
      _msg(v),
      if (open.isNotEmpty)
        _msg(ValidationResult(ValidationStatus.warning, 'lines',
            '${open.length} rader har ingen kategori. De räknas inte med i summan.')),
      const SizedBox(height: 8),
      const Text('Kategorier och momssatser kommer att kunna ställas in i nästa fas. '
          'Förslagen är endast ett restaurangexempel. Sparande kommer i fas 7.'),
    ];
  }
}
