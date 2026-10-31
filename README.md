# Bokföringsassistent

Lokal bokföringsassistent för småföretag i Sverige (Flutter, Android först). Allt sparas i telefonen. Inget sparas utan att du har godkänt uppgifterna.

## Hämta appen
1. Öppna fliken **Actions** på GitHub och klicka på den senaste gröna körningen av "Bygg Android-APK".
2. Längst ned under **Artifacts**: ladda ner **bokforing-apk** och packa upp zip-filen.
3. Installera `app-release.apk` på telefonen.

## Vad appen gör
- Skanna faktura/kvitto eller Z-rapport. Appen känner igen typen, läser datum, summa och moms, kontrollerar beloppen och visar allt för granskning.
- Egna försäljningskategorier med egen momssats (startguide och Inställningar).
- Månadstabell, årsöversikt, PDF-export och utskrift.
- Krypterad säkerhetskopia som du själv sparar och återställer.
- Valfri "Förbättrad analys online" (Google Gemini) med din egen API-nyckel. Avstängd som standard, frågar varje gång.

## Struktur
- `lib/domain/` ren logik: pengar i öre, moms (versionerade regler), klassificering, fakturor, Z-rapporter, kontroller, rapporter
- `lib/data/` SQLite-databas och Repository
- `lib/imaging/`, `lib/ocr/` bildförbättring och textigenkänning (offline)
- `lib/ai/` valfri onlineanalys
- `lib/export/` PDF och säkerhetskopia
- `lib/ui/` skärmar
- `test/` automatiska tester (körs på GitHub vid varje uppladdning)

Se `HANDOFF.md` för beslut och status.
