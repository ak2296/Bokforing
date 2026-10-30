import 'domain/z_extractor.dart';

/// Example texts used by the "Exempel" buttons and by tests.
const sampleInvoice = '''Nordisk Livs AB
FAKTURA
Fakturanummer: 20261045
Fakturadatum: 2026-10-27
Förfallodatum: 2026-11-26
OCR: 1234567890
Bankgiro 123-4567
Netto 1 000,00
Moms 25% 250,00
Totalt 1 250,00
Att betala 1 250,00 kr''';

const sampleChangeReceipt = '''Kvarnby Kök AB
Kvitto / Faktura
Fakturanummer: 7781
Datum: 2026-10-28
Pizzabagare 3 st   80,00
Totalt            80,00
Kontant          100,00
Växel             20,00
Moms 12%           8,57''';

const sampleMultiVat = '''Grossisten i Skåne AB
FAKTURA
Fakturanummer: 55120
Fakturadatum: 2026-10-26
Förfallodatum: 2026-11-25
Netto 8 000,00
Moms 25% 250,00
Moms 12% 120,00
Moms 6% 60,00
Summa moms 430,00
Att betala 8 430,00''';

const sampleZReport = '''Z-RAPPORT
Z-nummer: 0142
Datum: 2026-10-28
Mat 4 500,00
Konfektyr 300,00
Tobak 800,00
Öl 2 100,00
Wine 1 700,00
Sprit 900,00
Cider 500,00
Total försäljning 10 800,00
Kontant 3 000,00
Kort 7 000,00
Swish 800,00''';

/// Restaurant suggestions only. The user chooses categories and VAT rates.
const restaurantSuggestions = [
  SalesCategory(id: 'c0', name: 'Mat', vatRatePercent: 12),
  SalesCategory(id: 'c1', name: 'Konfektyr', vatRatePercent: 6),
  SalesCategory(id: 'c2', name: 'Tobak', vatRatePercent: 25),
  SalesCategory(id: 'c3', name: 'Öl', vatRatePercent: 25),
  SalesCategory(id: 'c4', name: 'Sprit', vatRatePercent: 25),
  SalesCategory(id: 'c5', name: 'Vin', vatRatePercent: 25),
  SalesCategory(id: 'c6', name: 'Cider', vatRatePercent: 25),
];
