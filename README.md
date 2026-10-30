# Bokföringsassistent (Flutter)

Lokal bokföringsassistent för småföretag i Sverige. Fas 1: grund, bokföringslogik, tester, bygg-skript.

## Få en APK utan Android Studio
1. Skapa ett gratis konto på github.com och ett nytt tomt (privat) repository.
2. Ladda upp ALLA filer i den här mappen (inklusive mappen `.github`). Använd "Add file → Upload files" i webbläsaren.
3. Öppna fliken **Actions**, välj "Bygg Android-APK" och tryck **Run workflow**.
4. När bygget är klart (några minuter): öppna körningen och ladda ner **bokforing-apk** under Artifacts.
5. Packa upp zip-filen, för över `app-release.apk` till telefonen och tillåt installation från okända källor.

Om bygget misslyckas: öppna den röda körningen, kopiera felmeddelandet och skicka det till Claude.

## Struktur
- `lib/domain/` ren Dart-logik utan Android-beroenden: Money (öre), VAT, klassificering, fakturautläsning, Z-rapport, validering
- `lib/main.dart` appskal och analysvy (klistra in text)
- `test/domain_test.dart` enhetstester

## Faser
1 grund (klar, ej kompilerad av författaren) · 2 kamera · 3 OCR · 4–6 utläsning i appen · 7 granskning/sparande · 8–9 rapporter · 10 PDF/utskrift · 11 backup/säkerhet · 12 test
