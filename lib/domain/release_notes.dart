/// What changed in each update, in plain Swedish for the owner. Newest first.
/// Add an entry with the next [id] for every release the owner should hear
/// about: the app shows it once after the update and lists it under
/// Inställningar → Mer → Nyheter.
class ReleaseNote {
  /// Counts up by one for each entry; the app remembers the highest it showed.
  final int id;
  final String date;
  final String title;

  /// (bold lead-in, rest of the sentence); the lead-in may be empty.
  final List<(String, String)> items;
  const ReleaseNote(this.id, this.date, this.title, this.items);
}

const releaseNotes = <ReleaseNote>[
  ReleaseNote(10, '19 november 2026', 'Redovisarpaket: se över och godkänn', [
    ('Gula rader:', 'tryck på en gul rad i Redovisarpaket så ser du allt som behöver ses över. Tryck på en punkt för att öppna dokumentet och rätta det.'),
    ('Godkänn:', 'vill du skicka ändå, till exempel när en Z-rapport skiljer på grund av rabatter, godkänner du det själv. Då kommer raden med i mappen.'),
    ('Z-rapporten:', 'appen föreslår kategorin även när namnet är avkortat, som Dryc.'),
  ]),
  ReleaseNote(9, '18 november 2026', 'Bättre läsning av Z-rapporter', [
    ('Belopp på raden ovanför:', 'när kameran läser beloppen en rad över namnen paras de ändå ihop rätt, både varugrupper och kort/kontant. Appen säger till att du ska kontrollera.'),
    ('Långa kvitton i delar:', 'det som syns på två bilder räknas bara en gång, även när texten lästs lite olika.'),
    ('Svårlästa kvitton:', 'rubriken för varugrupper och summan av försäljningskvitton hittas även när texten är otydlig. Grand total och bokföringsunderlag räknas aldrig som dagens försäljning.'),
    ('Kontant:', 'står det "Kontant" som betalningsvillkor föreslår appen Kontant under Betalades med (gult tills du har valt).'),
  ]),
  ReleaseNote(8, '17 november 2026', 'Kort och kontant i Z-rapporten', [
    ('Z-rapporten:', 'appen läser hur mycket som betalades med kort och kontant. Hittas bara ett av dem räknar appen ut det andra och markerar det gult.'),
    ('Bokföringen:', 'SIE-filen bokför kortdelen på företagskontot och resten på kassan.'),
    ('Redovisning:', 'ny Kassarapport med kontant och kort per dag.'),
  ]),
  ReleaseNote(7, '17 november 2026', 'Hur betalade du?', [
    ('Betalades med:', 'när ett kvitto eller en faktura är betald väljer du Bank / kort, Kontant eller Privat. Det styr vilket konto pengarna bokförs från, så kassan, banken och det du lagt ut själv stämmer för din redovisare.'),
    ('Efter skanning:', 'rutan är gul (Kontrollera) tills du har valt. Kvittot kan föreslå Kontant eller kort.'),
    ('Bankfilen:', 'fakturor med samma belopp bockas inte i förväg, och kvitton som redan är betalda med kort räknas som bokförda.'),
    ('Listan:', 'betalda poster har en grå etikett med hur de betalades.'),
    ('Balans:', 'det du betalat privat visas som egen insättning (enskild firma) eller skuld till dig (aktiebolag).'),
  ]),
  ReleaseNote(6, '17 november 2026', 'Nya flikar i Rapporter och veckokort i Utgifter', [
    ('Rapporter:', 'fem flikar i egna färger: Månad, År, Jämför (violett), Bokslut och Redovisning. Fliken har samma färg som rutan överst.'),
    ('Bokslut:', 'Resultat och Balans i samma flik. Balans visar tillgångar, eget kapital och skulder när du lagt in ingående balanser.'),
    ('Redovisning:', 'allt för din redovisare på ett ställe: Redovisarpaket, SIE-fil, bokföringsrapporter och balansunderlag.'),
    ('Utgifter:', 'fakturor och kvitton visas vecka för vecka, som Z-rapporterna.'),
    ('Försäljning:', 'onlineförsäljning har samma blå ruta som en Z-rapport, en etikett "Online" och beloppet i turkos.'),
    ('Påminnelser:', 'raden "Aviseringar i telefonen" visades två gånger. Nu en gång.'),
  ]),
  ReleaseNote(5, '17 november 2026', 'Beställ aktivering i appen', [
    ('Beställ aktivering:', 'under Inställningar → Aktivering skickar du en beställning med företagsnamn och organisationsnummer från Företag. Du får en veckas provperiod direkt.'),
    ('Koden kommer själv:', 'när betalningen är registrerad aktiveras appen av sig själv nästa gång du öppnar den. Du behöver inte klistra in något.'),
    ('Företagsuppgifter:', 'namn och organisationsnummer är låsta så länge appen är aktiv. Ändrar du dem slutar appen fungera tills du ändrar tillbaka.'),
    ('Användarguiden:', 'öppnas nu direkt och går snabbare på äldre telefoner.'),
  ]),
  ReleaseNote(4, '17 november 2026', 'Guide i appen och retur/kredit', [
    ('Användarguiden:', 'öppnas nu i appen med ett innehåll du kan trycka på för att hoppa till kapitlet.'),
    ('Retur/kredit:', 'kreditnota, returfaktura, returnota och returkvitto känns igen och dras av från utgifterna och momsen.'),
    ('Nyheter:', 'visningen efter en uppdatering väntar nu tills appen är redo, så den inte försvinner.'),
  ]),
  ReleaseNote(3, '16 november 2026', 'Redovisarpaket, balanser och perioder', [
    ('Redovisarpaket:', 'en knapp på Rapporter samlar månadsrapport, momsunderlag, verifikationslista, huvudbok, saldobalans, resultaträkning och SIE-fil. Spara som mapp, skicka med e-post eller välj papper att skriva ut.'),
    ('Perioder:', 'välj månad, kvartal, halvår eller år i Resultat och Redovisarpaket. Förvalet ställer du in under Företag → Redovisning.'),
    ('Din redovisare:', 'lägg in namn, e-post och mobilnummer. E-posten öppnas färdig med alla filer och ett sms kan förberedas efteråt.'),
    ('Ingående balanser:', 'lägg in bank, tillgångar och lån så får du en balansräkning (utkast), avskrivningsplan och lånplan.'),
    ('Rapporter:', 'ny design med en stor ruta överst i Månad, År och Resultat, och nya bokföringsrapporter.'),
    ('Nyheter:', 'den här sidan visar vad som är nytt efter varje uppdatering.'),
  ]),
  ReleaseNote(2, '16 november 2026', 'Kamerablixt, nya Jämför och påminnelser', [
    ('Blixt i kameran:', 'Av, Auto eller På. Knappen sitter uppe till höger när du skannar.'),
    ('Nya Jämför:', 'svaret först, procent och belopp, över samma månader i båda åren. Du ser största ökning och minskning och varje månad med två staplar.'),
    ('Påminnelser:', 'du ser och ändrar telefonens tillstånd för aviseringar. Utan tillstånd kommer inga påminnelser.'),
    ('Översikt:', 'diagrammet visar fem månader med bredare staplar.'),
    ('Användarguiden:', 'innehållsförteckningen går att trycka på.'),
  ]),
  ReleaseNote(1, '15 november 2026', 'Ny startsida i Inställningar', [
    ('Inställningar:', 'ny startsida med grupper, sökning och en omkopplare för ljust eller mörkt.'),
    ('Z-rapporter:', 'du ser vilka dagar som saknas och kan markera stängda dagar.'),
    ('Kostnadstyper:', 'lägg till egna kostnadstyper.'),
    ('Översikt:', 'aktiveringen och säkerhetskopian visas som ikoner uppe till höger.'),
  ]),
];

/// The id of the newest entry.
int get latestNoteId => releaseNotes.first.id;
