# Bokföringsassistent (Flutter)

Lokal bokföringsassistent för småföretag i Sverige. Allt körs på telefonen, inget skickas till någon server.

## Få en APK utan Android Studio
1. Skapa ett gratis konto på github.com och ett nytt (privat) repository.
2. Ladda upp ALLA filer i den här mappen (inklusive mappen `.github`).
3. Öppna fliken **Actions**, välj "Bygg Android-APK" och tryck **Run workflow**.
4. När bygget är klart: ladda ner **bokforing-apk** under Artifacts, packa upp och installera `app-release.apk`.

Om bygget misslyckas: kopiera felmeddelandet från den röda körningen och skicka det till Claude.
Stegen "flutter analyze" och "flutter test" får misslyckas utan att stoppa bygget. Titta i loggen om något är rött.
Appen byggs utan kodkrympning (R8), eftersom den förstörde ML Kit i den färdiga appen.

## Struktur
- `lib/domain/` ren Dart-logik: Money (öre), moms, klassificering, fakturautläsning, Z-rapport, validering, OcrDocument
- `lib/imaging/preprocess.dart` pappersdetektering, beskärning, kvalitet, rakning, kontrast
- `lib/ocr/mlkit_ocr.dart` ML Kit-textigenkänning (inbyggd modell, offline)
- `lib/ui/scan_page.dart` kamera med ram, kvalitetskontroll, OCR
- `lib/main.dart` appskal och analysvy

## Status
- Klart (ej kompilerat av författaren): grund, kamera, OCR, pappersbeskärning, fakturor och kvitton (inkl. momstabell), Z-rapport (enkel).
- Ännu inte: Z-rapport med sektioner (varugrupp/momsgrupp), flera bilder för långa kvitton, kantdetektering/perspektiv, granskning/sparande, databas, rapporter, PDF, backup.
