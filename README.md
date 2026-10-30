# Bokföringsassistent (Flutter)

Lokal bokföringsassistent för småföretag i Sverige. Allt körs på telefonen, inget skickas till någon server.

## Få en APK utan Android Studio
1. Skapa ett gratis konto på github.com och ett nytt tomt (privat) repository.
2. Ladda upp ALLA filer i den här mappen (inklusive mappen `.github`).
3. Öppna fliken **Actions**, välj "Bygg Android-APK" och tryck **Run workflow**.
4. När bygget är klart: ladda ner **bokforing-apk** under Artifacts, packa upp och installera `app-release.apk` på telefonen.

Om bygget misslyckas: öppna den röda körningen, kopiera felmeddelandet och skicka det till Claude.
Stegen "flutter analyze" och "flutter test" får misslyckas utan att stoppa bygget, så att du ändå får en APK. Titta i loggen om något testar rött.

## Struktur
- `lib/domain/` ren Dart-logik: Money (öre), moms, klassificering, fakturautläsning, Z-rapport, validering, OcrDocument (rad-rekonstruktion)
- `lib/imaging/preprocess.dart` bildkvalitet och förbehandling
- `lib/ocr/mlkit_ocr.dart` ML Kit-textigenkänning (inbyggd modell, fungerar offline)
- `lib/ui/scan_page.dart` kamera med ram, kvalitetskontroll, OCR
- `lib/main.dart` appskal och analysvy
- `test/` enhetstester

## Status
- Fas 1 grund: klar. Fas 2 kamera och fas 3 OCR: skrivna, ej kompilerade av författaren.
- Ännu inte gjort: automatisk kantdetektering och perspektivkorrigering, skuggreducering, automatisk bildtagning, granskning/sparande (fas 7), databas, rapporter, PDF, backup.
- Gränsvärden för "för mörk" och "suddig" är preliminära och måste kalibreras mot riktiga bilder. Kvalitetsskärmen visar de uppmätta värdena.
