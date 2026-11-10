# HANDOFF – Bokföringsassistent (Flutter)

Read this whole file first. It is the full context from a long chat with the owner (a non-developer who runs a small business in Sweden). Reply to the owner in plain language; all app UI text must be Swedish.

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

## 4. Current code layout (rewritten from scratch 2026-10-31, branch `ny-start`; old code kept locally in `_gammal_kod/`, not committed)
- `domain/` pure Dart: `money.dart` (öre, Swedish parse/format), `vat.dart` (VatRate in bp, VatCalculator, versioned `VatRuleSet.se2026` verified on skatteverket.se 2026-10-31: food 6 % 2026-04-01..2027-12-31, restaurant service 12 %), `dates.dart`, `models.dart`, `validation.dart` (AccountingValidationEngine), `reports.dart` (monthly/yearly, dynamic columns, derived totals), `category_templates.dart` (suggestions only, no VAT), `ocr_models.dart` (blocks/lines/words/boxes/confidence, row grouping), `text_patterns.dart` (amounts/dates/rates, Confidence, Extracted), `classifier.dart`, `document_parser.dart`, `invoice_parser.dart` (ranked total candidates, cash/change/card logic, VAT table/lines/net, dates incl. header-row layout), `z_report_parser.dart` (section detection, exact/remembered auto-match, possible-match suggestions, printed-rate mismatch warning), `text_merge.dart`.
- `data/database.dart` (sqflite schema v1) and `data/repository.dart` (only writer; audit log; duplicates; aliases).
- `imaging/preprocess.dart` (runs in isolate): orientation, paper crop (Otsu), quality (dark/bright/blur/skew/not found), deskew ±10° using text near paper, shadow reduction (background division), percentile contrast. No binarisation/sharpening, no perspective correction.
- `ocr/ocr_service.dart` ML Kit Latin, keeps boxes and confidences.
- `ai/` `gemini_client.dart` (generateContent REST, strict JSON schema, Swedish error messages, key in flutter_secure_storage, default model `gemini-3.8-flash`, editable in settings) and `ai_result.dart` (amounts parsed from printed text with Money.parse; Z rows matched with the same cautious matcher).
- `export/monthly_pdf.dart` (pdf package, A4 landscape) and `export/backup.dart` (AES-256-GCM + PBKDF2 encrypted JSON of all tables; images and API key excluded; restore in one transaction).
- `ui/`: setup wizard, shell (5 tabs + settings), dashboard, sales/expenses lists, reports (month table + PDF/print, year), record details (edit/delete with audit), history, scan (camera with frame + live "Dokument upptäckt" hint, long-document mode, processing states, quality screen), review pages for invoice and Z-report (confidence badges, alternatives, duplicates, "Kom ihåg" label mappings, AI offer card), settings (company, categories, keep images, backup, AI, privacy).

## 5. Status and honesty notes
- No Flutter/Java is installed on the owner's PC and the owner does not want local installs. All builds/tests run on GitHub Actions (`.github/workflows/build-apk.yml`, Flutter 3.47.9, runs on every push to any branch; analyzer warnings/errors and test failures fail the build; errors are written as annotations readable on the public run page).
- Verified on GitHub: analyze clean (infos only), unit + database (sqflite ffi) + parser + imaging + AI-mapping + backup/PDF tests, debug and release APK build. NOT verified on a phone yet: camera, ML Kit at runtime in the release APK (shrinking is off), printing, file picker, Gemini against the real API.
- Release APK is built with `--no-shrink` and `isMinifyEnabled = false` because R8 broke ML Kit earlier.
- Manifest edits in CI: minSdk 24, CAMERA, INTERNET (only for the optional AI step), `allowBackup="false"`.
- Gemini facts checked 2026-10-31 on ai.google.dev: free tier exists for `gemini-3.8-flash` and `gemini-3.5-flash-lite` (both image input + structured output); free-tier content "used to improve our products"; limits only visible in AI Studio.

## 6. Owner's real documents (what OCR/extraction must cope with)
- **Wholesaler invoice (A4, FAKTURA)**: "Fakturanr", "Kundnr", due-date header with the dates on the next row, "Momspliktigt belopp 491,87", "Moms 6% 29,47", "Moms 25% 0,00", "Öresutj. -0,34", "Att betala SEK 521,00", stamp "BETALD", QR code, supplier name in capitals. Extraction was close to right in the debug build (total and VAT correct).
- **Supermarket receipt**: "Totalt 598,90 SEK", "Mottaget Kontokort 598,90", VAT table "Moms% Moms Netto Brutto / 6,00 31,05 517,95 549,00 / 25,00 9,98 39,92 49,90".
- **Card receipt from a public body**: no VAT printed, "Totalt 200,00kr", "Kortbetalning".
- **Z-report, A4 version** (OCR text was good): sections include "Periodens försäljning kr 12 955,00", "Öresutjämning", "Betalningar", "Tjänster", "Varor", "Skulder", then **"Försäljning per varugrupp"** with rows such as Dryck, Dryck avhämtning, Mat 1 912, Mat avhämtning 1 507, Sprit, Tobak, Vin, Öl. Those rows (163+70+1 912+1 507+880+2 512+89+5 822) sum exactly to 12 955. Later sections: per momsgrupp, kvitto counts, grand total, bokföringsunderlag, "Kassalåda och växelkassa". Dated 2026-10-31.
- **Z-report, long thermal strip version**: vertical "EJ KVITTO PÅ KÖP" printed along both edges; photographed from far away the OCR was garbage (digits wrong, special characters lost). Needs close-ups (long-document mode) or the AI step. Some owner invoices are long with small print; A4 Z-reports also exist. **Layouts differ between cash registers and suppliers - do not hard-code one.**
- Many supplier invoices also arrive as PDF by email: plan a "Välj fil" import for PDFs/images (check packages first).

## 7. Remaining work
1. Owner tests the APK on the phone with real documents; tune thresholds and parsers from real OCR text (the review screen shows the OCR text).
2. "Välj fil" import of PDFs/images from email.
3. Optional biometric lock; perspective correction / edge detection.
4. UI (widget) tests for the main flows; architecture doc.
5. iPhone build (needs Apple Developer account).

## 8. Working rules
- Never fake OCR, never hard-code sample accounting records, never use floating point for money, never save silently, never let AI or fuzzy logic silently resolve a discrepancy, never assume one layout or one business type.
- Verify package APIs against current pub.dev/official docs; do not rely on memory.
- Keep the app small and free of tracking SDKs. Do not add INTERNET permission until the optional AI step needs it (then explain it to the owner).
- After each phase: compile, run tests, verify, then continue. Do not claim something works if it has not been run.
- The owner sees only a phone and (optionally) GitHub; tell them exactly which file/button when they must act, and keep their steps minimal.
