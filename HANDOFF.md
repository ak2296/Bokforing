# HANDOFF – Bokföringsassistent (Flutter)

Read this whole file first. It is the full context from a long chat with the owner (a non-developer who runs a small restaurant in Malmö, Sweden). Reply to the owner in plain language; all app UI text must be Swedish.

## 1. What the app is
A local-first Swedish bookkeeping assistant for small businesses (Android first, iPhone later; hence Flutter). The user photographs:
1. **Supplier invoices / receipts** ("Fakturor") -> extract date, total, VAT (per rate), supplier, invoice number, due date.
2. **Daily Z-reports** from the cash register ("Z-rapport") -> sales per category, daily total, date.

Pipeline (never skip a step): SCAN -> preprocess -> OCR -> classify -> extract -> validate -> SHOW USER -> USER CONFIRMS -> save locally -> monthly/yearly reports -> PDF/print.
**Nothing is ever saved without the user's explicit tap ("Godkänn och spara").** Accuracy and traceability beat automation. If uncertain, say so.

## 2. Owner's requirements and decisions (do not change without asking)
- All UI Swedish. Money SEK, Swedish format `1 250,50 kr`. Dates `2026-10-28`.
- **Money is integer öre everywhere. Never double.** (`lib/domain/money.dart`)
- VAT from a VAT-inclusive amount: `gross * r / (100 + r)` (125 kr @25% -> 25; 112 @12% -> 12; 106 @6% -> 6). Rates stored in basis points. Rules versioned in `vat.dart` (`VatRuleSet`).
- Skatteverket: from 1 April 2026 food sold as food/takeaway is 6%; food/drink served as restaurant service stays 12%. The app must NEVER assign VAT from a category name; the user picks the rate per category. The end date of the 6% rate (31 Dec 2027) is **unverified** (only a secondary source) - verify on skatteverket.se before relying on it.
- Z-report categories are user-defined (add/rename/delete/reorder, each with name + VAT rate). Restaurant examples (Mat, Konfektyr, Tobak, Öl, Sprit, Vin, Cider) are only suggestions. The monthly table and PDF columns must follow the user's categories dynamically.
- Z-report: do NOT force-match totals; show the difference, user resolves. The business date comes from the report, not the phone clock.
- Invoice total: never "largest number". Distinguish Att betala / Totalt / Summa from cash tendered, change (växel), netto, momspliktigt belopp, delsumma.
- Fuzzy category matching is cautious: only an exact name match auto-assigns. "Mat avhämtning" must NOT auto-match "Mat" (different VAT possible). Uncertain -> "Vi hittade en möjlig matchning", user confirms.
- Duplicate detection (invoices: supplier+number+date+amount; Z-reports: date+Z-number+total) with "Visa befintlig" / "Registrera ändå".
- Local Room-like database (in Flutter: SQLite, e.g. drift or sqflite - check current pub.dev versions), audit trail, backup/import (encrypted JSON via file picker), optional biometric lock, no analytics, no ads, no INTERNET needed for the base app.
- Monthly table (Datum | categories... | Summa | Utgifter | Moms), monthly totals ("Beräknad moms" wording, not legal tax filing), yearly dashboard (Månad, Försäljning, Utgifter, Utgående moms, Ingående moms, Momsdifferens = utgående - ingående), PDF export + printing, history screen, first-run wizard, settings. Full original spec is summarised in section 7.
- Owner wants: **free, small app (no big on-device model), minimal user steps, no server.**

## 3. AI decision (most important recent decision)
Rule-based extraction cannot understand arbitrary invoice/Z-report layouts (every new layout showed a new gap). The owner wants the app to genuinely understand documents. Decision:
- Keep the deterministic reader as the offline first pass and fallback.
- Add an **opt-in "Förbättrad analys" button/step using the Gemini API free tier** (a Flash model with image input; check current model names and free limits in Google AI Studio and https://ai.google.dev/gemini-api/docs/pricing before coding; vision support of each free model is not yet confirmed).
- Flow: local read -> run deterministic validation -> **only if checks fail or fields are missing, offer "Förbättrad analys online"** (saves quota and adds no steps for normal documents). Never send anything silently; show a clear Swedish warning each time about what is sent (the document photo) and to whom (Google). Off unless the owner has pasted an API key in Inställningar.
- The AI only *suggests* structured JSON (document type, date, supplier, invoice no., total, VAT per rate, Z-report category rows, etc.). Its output must pass `AccountingValidationEngine` and the review screen. **The AI never decides final amounts; arithmetic stays in deterministic code.**
- Key handling: the owner pastes their own free AI Studio key once in Inställningar (stored in secure storage, e.g. flutter_secure_storage). Do not hard-code a key into a build that other people will use.
- Privacy facts the owner has been told: Google's terms say unpaid-tier content may be used to improve products and read by reviewers, but the terms page says the paid-service data terms apply to EEA/CH/UK usage including free quota (owner should verify in the terms). Google also says developers who distribute API clients to users in those regions must use paid services - relevant only if the app is ever given to others. App is currently for the owner's own business only.
- Free limits are shown only inside the owner's AI Studio account, per project, not guaranteed.
- No on-device LLM (too large). Do not add one unless asked.

## 4. Current code layout (all under `lib/`)
- `domain/money.dart` Money(öre), `Money.parse` (Swedish/OCR formats; returns null on ambiguous like "1.250"), `format`.
- `domain/vat.dart` VatRate (basis points), VatCalculator (fromGross/fromNet, integer rounding), VatRuleSet guidance.
- `domain/patterns.dart` date/amount regexes, `Confidence` enum.
- `domain/classifier.dart` weighted keyword classifier -> invoice / zReport / unknown + confidence (below 0.7 -> user must choose).
- `domain/invoice_extractor.dart` candidate ranking for total, VAT per rate (incl. "Moms% Moms Netto Brutto" table, "Momspliktigt belopp" = taxable base), dates, due date (also on the row below a "Förfallodatum" header), supplier (prefers a line with AB/HB/KB), invoice number, OCR ref.
- `domain/z_extractor.dart` Z-report: uses only the "Försäljning per varugrupp" section when present; total from "Periodens försäljning"/"Total försäljning"/...; cautious fuzzy category matching (`suggestedId` vs auto `categoryId`); `sumWith(overrides)`.
- `domain/validation.dart` AccountingValidationEngine (reconcileZReport, checkInvoiceArithmetic, checkVatBreakdown, checkVatLine, checkVatPlausible).
- `domain/ocr_document.dart` rebuilds table rows from OCR lines, with page-tilt compensation (label and amount on the same row).
- `domain/text_merge.dart` merges text from several photos of one long document (overlap detection).
- `imaging/preprocess.dart` orientation fix, crop to guide frame, find the bright paper (Otsu) and crop to it, brightness/sharpness quality checks, deskew (<= ~7 deg), contrast stretch. No binarisation/sharpening (would erase decimal commas). No perspective correction / edge detection yet.
- `ocr/mlkit_ocr.dart` ML Kit text recognition (Latin, bundled model).
- `ui/scan_page.dart` camera with frame + "Långt dokument" multi-photo mode, quality screen ("Bildkvaliteten är för låg", "Skanna igen" / "Använd ändå"), SafeArea.
- `main.dart` shell (5 tabs + settings icon) and a temporary analysis page: paste/scan text -> classify -> extract -> show review. **No save, no database, no settings, no reports yet** (tabs other than Skanna are placeholders). Z-report review has per-row category dropdown using the hard-coded restaurant suggestions.
- `samples.dart` example texts. `test/` unit tests for all domain logic.

## 5. Status and honesty notes
- The previous assistant had **no Flutter/Dart/Android SDK and could not compile or run anything**. Code was ported from a JavaScript prototype whose logic was run in Node. **Run `flutter pub get`, `flutter analyze`, `flutter test` first and fix whatever fails.** Treat all tests as unverified until run.
- One real bug was found by the owner's CI build and fixed in the last zip: `z_extractor.dart` lacked `suggestedId`/`sectionFound`/`sumWith` (a lost edit). Make sure the current files compile.
- Build results so far: the first debug/release builds worked after adding R8 rules. **The release (R8-shrunk) build crashed at runtime inside ML Kit** (NullPointerException with obfuscated names); the **debug build works**. Current workaround: Gradle `isMinifyEnabled=false` and `--no-shrink`. Verify the release APK now runs OCR, or keep shrinking off.
- The CI workflow (`.github/workflows/build-apk.yml`) runs `flutter create --platforms=android,ios` in the repo (so `android/` and `ios/` are generated, not committed), sets `minSdk 24`, adds CAMERA permission, writes ProGuard keep/dontwarn rules for ML Kit, then builds release and debug APKs. Adjust if you commit the platform folders.
- Package versions chosen (from pub.dev search): camera ^0.12.0, google_mlkit_text_recognition ^0.15.0, image ^4.2.0. Flutter stable 3.47.x was used by CI. Re-check versions.
- Quality thresholds (`_minBrightness` 70, `_minSharpness` 60) are provisional; the owner's real photos measured brightness 123-158 and sharpness 334-1417.

## 6. Owner's real documents (what OCR/extraction must cope with)
- **Centrumgrossisten AB invoice (A4, FAKTURA)**: "Fakturanr", "Kundnr 999", due-date header with the dates on the next row, "Momspliktigt belopp 491,87", "Moms 6% 29,47", "Moms 25% 0,00", "Öresutj. -0,34", "Att betala SEK 521,00", stamp "BETALD", QR code, supplier line "CENTRUMGROSSISTEN AB". Extraction was close to right in the debug build (total and VAT correct).
- **Willys receipt**: "Totalt 598,90 SEK", "Mottaget Kontokort 598,90", VAT table "Moms% Moms Netto Brutto / 6,00 31,05 517,95 549,00 / 25,00 9,98 39,92 49,90".
- **Lunds Universitet card receipt**: no VAT printed, "Totalt 200,00kr", "Kortbetalning".
- **Z-report, A4 version** (OCR text was good): sections include "Periodens försäljning kr 12 955,00", "Öresutjämning", "Betalningar", "Tjänster", "Varor", "Skulder", then **"Försäljning per varugrupp"** with rows such as Dryck, Dryck avhämtning, Mat 1 912, Mat avhämtning 1 507, Sprit, Tobak, Vin, Öl. Those rows (163+70+1 912+1 507+880+2 512+89+5 822) sum exactly to 12 955. Later sections: per momsgrupp, kvitto counts, grand total, bokföringsunderlag, "Kassalåda och växelkassa". Dated 2026-10-31.
- **Z-report, long thermal strip version**: vertical "EJ KVITTO PÅ KÖP" printed along both edges; photographed from far away the OCR was garbage (digits wrong, special characters lost). Needs close-ups (long-document mode) or the AI step. Some owner invoices are long with small print; A4 Z-reports also exist. **Layouts differ between cash registers and suppliers - do not hard-code one.**
- Many supplier invoices also arrive as PDF by email: plan a "Välj fil" import for PDFs/images (check packages first).

## 7. Remaining work, in suggested order
1. Get the project compiling; `flutter test` green; confirm release APK runs OCR.
2. **Settings + first-run wizard**: company name, user-defined categories with VAT rate (replace `restaurantSuggestions`), remembered label->category mappings (learn from user corrections, e.g. "Dryck avhämtning" -> chosen category), versioned VAT guidance hints (never auto-assign).
3. **Gemini "Förbättrad analys"** as in section 3 (prompt returns strict JSON; validate with the engine; consent dialog in Swedish; key in secure storage; offline fallback; handle quota/network errors with clear Swedish messages).
4. **Review/confirm screen** (editable fields, confidence badges, document preview, "Godkänn och spara / Redigera / Skanna igen / Avbryt"), manual entry (Faktura and Z-rapport), duplicate detection.
5. **Local database** (money as öre; entities: BusinessProfile, Category, DailySales, DailySalesItem(with category name + VAT snapshot), Invoice, InvoiceVat(rate, vat, net, printed vs calculated), DocumentScan(OCR text, optional image), AuditLog). Totals are derived, never stored. Record created/modified time, source, OCR vs manual, confirmed, edits audit trail.
6. **Reports**: dashboard, monthly table (dynamic columns, tap a day for its invoices), yearly dashboard, history screen; PDF export (pdf package) and Android print.
7. Backup/import (SAF), optional biometric lock, "Behåll originalbilder" setting, privacy text in Swedish.
8. Image quality: perspective correction/edge detection, shadow reduction, auto-capture suggestion (visible, never silent).
9. iPhone build (needs Apple Developer account; verify iOS OCR options).
10. UI tests for the main flows; README + architecture doc.

## 8. Working rules
- Never fake OCR, never hard-code sample accounting records, never use floating point for money, never save silently, never let AI or fuzzy logic silently resolve a discrepancy, never assume one layout or one business type.
- Verify package APIs against current pub.dev/official docs; do not rely on memory.
- Keep the app small and free of tracking SDKs. Do not add INTERNET permission until the optional AI step needs it (then explain it to the owner).
- After each phase: compile, run tests, verify, then continue. Do not claim something works if it has not been run.
- The owner sees only a phone and (optionally) GitHub; tell them exactly which file/button when they must act, and keep their steps minimal.
