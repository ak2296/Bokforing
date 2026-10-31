# Bokföringsassistent

Lokal bokföringsassistent för småföretag i Sverige (Flutter, Android först). Allt sparas i telefonen.

## Hämta appen
1. Öppna fliken **Actions** på GitHub och välj den senaste gröna körningen av "Bygg Android-APK".
2. Ladda ner **bokforing-apk** under Artifacts, packa upp och installera `app-release.apk`.

## Status (fas 1)
- Klart: pengar i öre, momsberäkning, kontrollmotor, databas, startguide, inställningar med egna kategorier och momssatser, översikt, försäljning, utgifter, månadstabell och årsöversikt.
- Nästa fas: kamera, textigenkänning, granskning och manuell registrering.

## Struktur
- `lib/domain/` ren logik utan Flutter: Money, moms (versionerade regler), validering, rapporter
- `lib/data/` SQLite-databas och Repository (all läsning/skrivning)
- `lib/ui/` skärmar
- `test/` enhetstester och databastester
