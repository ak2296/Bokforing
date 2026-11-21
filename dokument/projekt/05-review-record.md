# 05 – Review and inspection record

Items reviewed: code, user interface, security and privacy, build pipeline, and the project documents themselves.
Baseline: commit `8204b71`, release `v2026.11.13i`.

## 1. Method and limits

| Review | Method | Done by | Limits |
|---|---|---|---|
| UX and information architecture | Heuristic review of the screens against usability rules, using the code and the owner's phone screenshots | Developer (Claude Code) with the owner | No user testing with other people; TalkBack not run |
| Code and design | Reading the code and the generated code graph; checking dependency direction, error handling and the money rules | Developer (Claude Code) | No coverage numbers; no second human reviewer |
| Security and privacy | Checking where data is stored and sent, what permissions are requested, how secrets are kept | Developer (Claude Code) | Not a penetration test; no external audit |
| Build and release | Reading the CI workflow and release steps | Developer (Claude Code) | Signing secret not inspected, only its effect (certificate check in CI) |
| Documents | Comparing documents with the code and the shipped behaviour | Developer (Claude Code) | Print booklet pages not re-inspected after the last text changes |

Status values: **Open**, **Partly fixed**, **Fixed** (in code, not always seen on a phone), **Accepted** (owner decided to keep), **Pass** (reviewed, no action).

## 2. Findings

### 2.1 Defects found and corrected (see also 04 §5)

| ID | Finding | Sev. | Status | Evidence / fix |
|---|---|---|---|---|
| F-01 | Warning and "Osäker" fields unreadable in dark mode (light fills reused) | High | Fixed | Dark-aware palette, commit `5b4ad2a` |
| F-02 | Date fields too narrow, text cut off | Medium | Fixed | Dates stacked full width |
| F-03 | Text fields had no fill and looked inactive next to dropdowns | Medium | Fixed | `3e28517` |
| F-04 | Cards in a row had unequal height | Low | Fixed | `IntrinsicHeight`, `6ea5585` |
| F-05 | Scan button hidden under the floating nav bar | Medium | Fixed | `2d293f2` |
| F-06 | "Importera fil" failed once with an error | Medium | Partly fixed | Errors now caught with a plain message; **root cause unknown**, ask the owner for the message if it returns |

### 2.2 Usability and accessibility

| ID | Finding | Sev. | Status | Notes |
|---|---|---|---|---|
| F-07 | Contrast: pumpkin `#E2600D` on white is about 3.6:1; selected tab label and orange chips are below 4.5:1 for small text | Medium | Open | Proposed: darker orange for text on light surfaces |
| F-08 | Small text (nav labels 10.5, charts 10, weekday chart 9.5, chips 11); nav labels cannot wrap; large system fonts untested; few screen-reader labels | Medium | Open | Test with large font and TalkBack |
| F-09 | Some messages still show raw exception text (for example "Det gick inte att spara: …", "Guiden kunde inte öppnas: …") | Medium | Partly fixed | Import messages fixed; others remain |
| F-10 | Review form is one long page; no "N fields to check" summary or jump to the first uncertain field | Medium | Accepted | Owner chose to skip for now |
| F-11 | Several routes to the same records (Översikt, lists, Rapporter, Historik) | Low | Partly fixed | "Visa historik" removed from Översikt; Historik remains under Inställningar → Data |
| F-12 | Delete is three taps deep; no undo after delete | Low | Open | Confirmation dialog exists |
| F-13 | Inconsistent words (papper, dokument, faktura, kvitto, registrering) | Low | Partly fixed | "papper" → "dokument"; "Faktura / kvitto" |
| F-15 | Two confidence levels (Kontrollera, Osäker) were hard to tell apart | Medium | Fixed | One orange level |
| F-17 | Empty screens had no next step | Low | Partly fixed | Översikt says "Börja med att skanna ditt första dokument"; other empty states unchanged |
| F-18 | Backup status and settings were buried | Medium | Fixed | Backup card on Översikt; settings grouped and searchable |
| F-19 | Calculated moms did not say when invoices were incomplete | Medium | Fixed | "Fyll i" notice under the moms figure |
| F-20 | Dates had to be typed with dashes | Low | Fixed | Digits only, dashes inserted |
| F-21 | Amounts shown differently in fields and cards | Low | Fixed | Thousands separator when not editing (not yet seen on a phone) |
| F-22 | PIN: feedback on a wrong PIN; warning when a forgotten PIN means data loss | Medium | Fixed | Warning shown when the PIN is set; shake and vibration added; recovery path itself not traced |

### 2.3 Functional and design

| ID | Finding | Sev. | Status | Notes |
|---|---|---|---|---|
| F-23 | On an Onslip invoice the supplier was read as "FAKTURA" (the word after "Avsändare:") instead of the company name | Medium | Open | Parser rule needed; add a regression case |
| F-24 | Learning also stores labels for dates; a wrong learned label could pick a wrong date | Low | Accepted | Owner decided to keep learning as is; entries can be removed under Inlärda fält |
| F-25 | Counting date changed to the due date; no automated test of the rule (see G-1) | Medium | Open | Add tests |
| F-26 | No test of database upgrade from old versions (G-3) | High | Open | Customers update by hand and may skip versions |

### 2.4 Security, privacy and portability

| ID | Finding | Sev. | Status | Evidence |
|---|---|---|---|---|
| F-14 | Privacy and security review | – | Pass, with notes | Network library is used only in `lib/ai/gemini_client.dart`; the INTERNET permission exists only for the optional online reading, after consent; `allowBackup` is false; PIN is a salted hash (15 000 iterations) in secure storage; backup is encrypted; activation uses an Ed25519 public key. Notes: PIN hash iterations are modest; forgotten backup password cannot be recovered (stated in the UI) |
| F-16 | Portability: domain code has no Flutter imports | – | Pass | `lib/domain` is plain Dart |
| F-28 | Nav bar tap feedback was hidden behind the cards (the splash was painted on the page surface); a first attempt painted it on the bar itself, which was not wanted | Low | Fixed (page-level flash, to be confirmed on a phone) | `shell.dart` `_FlashLayer` |
| F-29 | On a Clas Ohlson receipt the supplier was read as "(C Clas Ohlson" (the round logo read as a bracket and a letter), and the narrow receipt strip gave small print and many misread words | Medium | Fixed (to be confirmed on a phone) | Stray bracket and letter in front of a name are removed; small print triggers a second reading enlarged two times |
| F-30 | On a Z-report "Vin" was read as "Vir": the amount stayed on an unrecognised row while Vin showed 0; the owner had to mark it by hand | Medium | Fixed (to be confirmed on a phone) | A name one letter off exactly one category that is not yet on the report is suggested (needs confirmation). The guide now recommends "I delar" for narrow, long papers (pages 6 and 9) so the print comes out larger |
| F-31 | Field test 2026-11-15: the home hero card had the same green as Försäljning; the icon arrow pushed the mark off centre; cost type showed as chosen in the edit page without being saved (a suggestion) and as plain text on the faktura page; no way to add a cost type; no types for a-kassa and music/TV; lönebesked opened straight in edit mode; invoices with a due date label sometimes gave no due date; a line "Datum: …" was read as supplier; the start frame on a Z-report photo cut the top (date, Z number) | Medium | Fixed (to be confirmed on a phone) | Own indigo hero; shorter arrow, mark centred; cost type yellow (Kontrollera) until chosen, red "Ej vald" on the faktura page; own cost types (Inställningar → Utgifter och dokument → Kostnadstyper, or "+ Ny kostnadstyp" in the list); new types Avgifter och medlemskap (6980) and Musik och TV (6990); lönebesked detail page with Redigera; loose date after a due date label is taken as the due date (marked); lines with a date are not a supplier; the start frame is larger, most at the top. Räkningar pill and backup icon on Översikt, moms card under the hero |
| F-32 | Z-report count showed only a number, a missing Z-report day was not noticed, and unplanned closed days had nowhere to be marked; Inställningar was a long list of folding cards | Medium | Fixed (to be confirmed on a phone) | "N av X" in the Försäljning hero (X = days so far that are not closed); a tappable yellow alert for missing days opens a box with Skanna Z-rapporten and Butiken var stängd (x closes without change); closed weekdays and single days under Inställningar → Försäljning → Stängda dagar; Försäljning gets slate blue as its colour, the overview hero stays green; Inställningar redone as a home (company card, appearance switch, rows grouped as Verksamheten, Trygghet, Övrigt) with one page per group |
| F-33 | Field test: a narrow thermal Z-report was read with garbled labels (too few pixels across); the activation sat as a line at the bottom of Översikt; Utseende took too much room; the moms and weekday titles did not say what period or number they show | Medium | Fixed (to be confirmed on a phone) | A narrow strip may keep a longer side and is enlarged (up to 2.5 times) before reading; activation is a lock icon at the top (green or red, dialog with date and button); Utseende is a sun/moon switch; titles say the month and that the weekday bars are the average sales in kr; the printed guide has a page inside the front cover explaining that the in-app guide follows the app |
| F-34 | Notifications: the CI manifest patch did not declare POST_NOTIFICATIONS (Android 13+ never shows reminders without it), and the permission was only asked when a reminder was switched on, with no way to see or change it | Medium | Fixed | Permission declared in the build; Påminnelser has a switch showing the phone permission (asks, or opens Android notification settings; re-read on return) |
| F-27 | Build and release pipeline | – | Pass, with notes | Analysis and tests gate the build; signing certificate verified in CI with a fixed key. Notes: the signing key secret is a single point of failure (R-03); the build number has never been raised from 2 and CI does not set it (R-04) |

## 3. Document inspection

Each project document was compared with the code and the shipped behaviour.

| ID | Document | Finding | Sev. | Status |
|---|---|---|---|---|
| DOC-1 | `HANDOFF.md` | Out of date in places: describes database schema v1 (now v9), branch `ny-start`, and an early file layout; still correct on the owner's decisions and rules | Medium | Open |
| DOC-2 | `PRODUCT.md` | Current; written 2026-11-13; open decisions (pricing, accountant workflow) are marked | – | Pass |
| DOC-3 | `FUTURE_FUNCTIONS.md` | Current; lists parked company-only functions | – | Pass |
| DOC-4 | User guide (A5 PDF, version 1.3) | Updated for the changes up to the tour and tax estimate; the phone mock-up on the tab page still shows the old amber "Att betala" banner, not the new half-width cards | Low | Open |
| DOC-6 | User guide was hard to read: the A5 page opened on a phone is shrunk to about 44 % (body text about 4 pt), and the A6 booklet was A5 scaled to 71 % (about 6.8 pt) | Medium | Fixed (to be confirmed on a phone and on paper) | The app now carries a phone version (page 70 mm wide, body 10.5 pt, one column). The booklet is set at A6 size (body 8.8 pt) and cut into pages by `paginera_a6.py`; it has 32 pages (about 3 mm thick). The box was resized to 109 x 152 x 7 mm so the card lies on top of the A6 booklet |
| DOC-7 | User guide: sketches showed the old app (amber banner, old fields), pages were half empty or held only a picture or a box, pictures were very large, the contents list ran over two pages, and empty "Anteckningar" pages | Medium | Fixed (to be confirmed on paper and phone) | Sketches redrawn after the current app (overview, review screens, Z-report, expenses, reports); the A6 pages are cut by `paginera_a6.py` (headings kept with text, pages evened out, sketches small beside the text); "Anteckningar" removed; two pages added (Snabbguide, Ordlista); the phone version is one tall page per chapter (no page break inside a chapter) with no page numbers in the contents list; the home-print version with four pages per sheet is removed, only the printer's file (A6 + bleed) is made |
| DOC-8 | The overview screen was redesigned (result card, status rows, one trend card, latest list); the guide sketches and the contents of page 5 showed the old layout | Low | Fixed | Sketch and text on the tab page updated |
| DOC-9 | Cover pages: the A6 and phone covers had the phone sketch over the tagline, the packaging front had the devices crowding the tagline and cut at the edge; the long tagline was replaced by "Enklare bokföring i mobilen." on all covers; the contents list of the guide is now clickable (PDF links to each chapter) | Low | Fixed | Sketch moved/shrunk, one-line tagline, section anchors and links; checked in rendered pages |
| F-35 | Scan camera had no flash control | Low | Fixed | Flash button in the camera bar cycles Av, Auto, På (torch); the choice is kept while the app runs; guide chapter 4 updated |
| F-36 | Overview trend showed only 3 months with thin bars; guide covers (A6, phone) used a different sketch layout than A5 and were cut off; the download card had square corners | Low | Fixed | Chart shows at least 5 months with wider bars; A6 and phone covers use the A5 layout (phone fully visible vertically); card has 3.5 mm rounded corners at the trim line; checked on rendered previews |
| DOC-10 | Guide covers: the phone sketch on the A6 and phone covers was a live copy of the page sketch and was changed by the phone/A6 stylesheets (cut at the bottom, a green strip beside it in the A6 bleed); fixed by drawing the sketch once as an image (dokument/bilder/cover-phone.png) used by all three covers, with the A6 phone running into the bleed; checked on the rendered PDF pages, not only the HTML | Medium | Fixed | Same phone image on A5, A6 and phone covers |
| F-37 | The Jämför page was a chip row, one line chart and a plain 12-row table with no answer; redesigned keeping the concept (year against year, month by month, Försäljning/Utgifter/Moms, PDF/Excel/print): answer-first hero (percent and amount, same months in both years while the year is running), year picker with swap, segmented metric switch with per-metric colour, biggest rise and fall, month list with paired bars, both figures and change pill | Medium | Fixed | New page layout; 1 new unit test for the so-far totals and biggest rise/fall |
| F-38 | After an update the owner had no way to learn what changed | Low | Fixed | Nyheter page under Inställningar → Mer (release notes in lib/domain/release_notes.dart, newest first, dot until read) and a one-time sheet after an update (not on a new install); 1 unit test; guide updated; previewed and confirmed before building |
| F-39 | Bookkeeping reports a company keeps (journal, general ledger, trial balance) did not exist | Medium | Fixed | Ledger built from the SIE verifications (lib/domain/ledger.dart); Verifikationslista, Huvudbok, Saldobalans and Resultaträkning (BAS) as PDF, Excel and print on the Resultat tab; report PDFs get a tinted header and zebra rows; 2 unit tests; without opening balances, labelled as based on what is registered |
| F-40 | Reports page tabs were plain titles and tables; no balance data; no single hand-over for the accountant | Medium | Fixed | Hero card on Månad, År and Resultat; Ingående balanser page (bank, assets, loans, equity as the rest) with Balansräkning (utkast), write-off and loan plans; Momsunderlag (boxes 05, 10-12, 42, 48, 49); Redovisarpaket page (checklist with what is missing, ZIP folder, send files, choose papers to print with page counts); tests for balances, ledger, momsunderlag and the package PDFs; previewed and confirmed |
| F-41 | Reports can be handed over per month, quarter, half-year or year (default set under Inställningar → Företag → Redovisning); accountant name, e-mail, mobile and owner e-mail stored on the phone; the package opens the mail app with recipient, subject, text and all files, then offers a prefilled SMS (the SMS app opens, the user sends); the packaging depth is recomputed from the A6 booklet page count (dokument/verktyg/tjocklek.py: 36 pages, depth 7 mm still enough) | Medium | Fixed | New ReportPeriod, AccountingPage, PeriodPicker; flutter_email_sender and url_launcher added; CI manifest gets package visibility for mail and SMS; 3 period tests |
| F-42 | The Nyheter sheet could vanish at once after an update (shown while Android restarts the app, and marked seen at once); credit papers under other names (returfaktura, returnota, returkvitto, korrigeringsfaktura, credit note ...) were not recognised and the label said only Kreditnota; the guide opened in another app, whose edit tools reacted to taps and whose contents links did not work | Medium | Fixed | Sheet waits 0,9 s and counts as seen only if it stayed or was closed by the user; Retur/kredit wording and word list with whole-word matching (Returadress and the Systembolaget return-by line are not returns); in-app guide reader with tappable contents (printing raster, no new dependency); tests added |
| F-43 | The in-app guide was slow to open and heavy on an old phone: it rendered all 17 tall PDF pages to PNG at every start (about 30 million pixels, roughly 125 MB of RAM, and some pages taller than an old phone's largest texture) | Medium | Fixed (to be confirmed on an old phone) | The guide is cut on the PC (`make_guide_bilder.py`, run by `make_docs.py`) into WebP slices, 900 px wide and at most about 1200 px tall, in `assets/guide/`; the reader loads only the slices near the screen. The PDF asset and the "Öppna i en annan app" fallback are removed (the PDFs stay in `dokument/`) |
| F-44 | Settings → Företag: the text under "Mina företagsnamn" and the name chips touched the "Lägg till namn" field | Low | Fixed (to be confirmed on a phone) | More space above the heading (bold), between the description, the chips and the field |
| F-45 | Activation went through e-mail both ways and needed copying a code by hand; no trial; Quee Nycklar had no lock | Medium | Fixed (to be confirmed on two phones) | Quee: Aktivering has Beställ aktivering, which sends the company name and org number from Företag to the owner and starts a one-week trial (one per name and org number pair, hashed; the org number must pass the check digit). The code returns to the app and activates it by itself. Changing the name or number makes the trial or code inactive (status mismatch); the fields are locked while active. Quee Nycklar: 4-digit PIN with fingerprint (3 free tries, then 30 s to 1 h waits), a Beställningar tab (Ny, Betald, Skickad, Avslagen; Skapa kod only after Betald; owner login; orders deleted after 30 days) and the old code form as fallback. Firestore over REST with anonymous sign-in for customers; rules in `firebase/firestore.rules` (outside the repository). Not built: the 15-minute background check with a notification in Quee Nycklar |
| F-46 | The owner's test code 0000 was still accepted; the order card was hidden when the app ran on it | Low | Fixed | The test code is removed from the licence checker (a test checks it is refused). Earlier app versions keep accepting it until 2027-11-05. Quee Nycklar: the key opened on another thread failed with "Illegal argument in isolate message" because the closure carried the screen's objects; it now starts from a top-level function (test added) |
| F-47 | Inställningar → Påminnelser showed the line "Aviseringar i telefonen" twice | Low | Fixed | The duplicate line is removed |
| F-48 | Rapporter: Resultat held everything (SIE, bokföringsrapporter, balansräkning); Jämför shared the blue of År; online sales had a brown badge and "Online" only as text; Utgifter was one long list; Tillgångar choices were not explained | Medium | Fixed (to be confirmed on a phone) | Five tabs in their own colours (Månad, År, Jämför violet, Bokslut, Redovisning petrol); Bokslut has Resultat and a new Balans screen; Redovisning holds Redovisarpaket, SIE, bokföringsrapporter and balansunderlag; Utgifter in week cards (shared with Försäljning); online sales keep the blue badge and get an "Online" chip and a teal amount; the guide explains each Tillgångar and skuld choice |
| F-49 | Paid receipts and invoices were all booked from the bank account, so cash and privately paid purchases made Kassa, Företagskonto and the owner's debt wrong for the accountant | Medium | Fixed (to be confirmed on a phone) | New field Betalades med (Bank / kort, Kontant, Privat) per paid invoice, yellow until confirmed after a scan, asked when marking as paid; the SIE file and ledger book from 1930, 1910, or 2018/2893 by company form; the balance sheet counts private payments; the bank file keeps same-amount matches unticked, notes a fit with an already paid card receipt, and lists registered card receipts as already booked |
| F-50 | The Z-report's card and cash amounts were not read or saved, and the SIE file booked all takings on Kassa | Medium | Fixed (to be confirmed on a phone) | The reader finds card and cash by their labels (Betalmetoder first, till rows ignored) and works out the missing one from the day's sales (yellow); they are saved with the Z-report (database version 11) and shown inside it; the SIE file books card on 1930 and the rest on 1910; Redovisning has a Kassarapport. Till figures (cash in, out, left) were considered and left out: not needed in any report |
| F-51 | Z-reports: amounts read a line above their names were paired with the wrong name (card 5 105,00 lost, every category shifted by one); photos of a long receipt repeated their overlap; a garbled varugrupp heading was not found and all-time sums could be taken as sales; the Z number was read from a date; payment terms "Kontant" on their own line did not preselect Kontant | Medium | Fixed (to be confirmed on a phone) | An amount-first reading competes with the plain one and the row shifts and wins a tie; card and cash come from the reading where both add up; photos are joined at a loosely matched overlap, cut in its middle; fuzzy varugrupp heading and Försäljningskvitton total; Grand total, Bokföringsunderlag and account rows ignored without a section; cash terms suggest Kontant (yellow) |
| F-52 | In Redovisarpaket a yellow row (for example Kontrollrapport) looked unselected and could not be opened; the owner could not reach the Z-report to fix it or accept a known difference | Medium | Fixed (to be confirmed on a phone) | Yellow rows open one list of all points, each opening where it is fixed; a second confirmation puts the yellow rows into the package; fixed points turn normal again. Also: a cut-off or junk-padded category name ("Dryc") is suggested, never assigned |
| F-53 | The in-app update stopped with "Kontrollera nätverket" on a slow connection (the 117 MB file from GitHub took minutes and any drop ended the whole download) | Medium | Fixed (to be confirmed on a phone) | The download carries on from where it stopped (up to 6 tries, 30 s without data counts as a drop) and removes older update files from the cache first; `app_update_test` covers the resume; a failed download now shows the real reason (no contact, memory full, HTTP code) with its technical name; a failed download and a failed install are told apart (the old text said "download failed" for both), and the installer answer is shown |
| F-54 | The Lagring page spun for ever and showed nothing on the owner's phone | Medium | Mitigated, cause not found (to be confirmed on a phone) | Counting now ends after 40 seconds or on any error; the page then says so (with the error name) and offers "Försök igen"; any error while walking a folder only leaves that folder out of the count, instead of failing the whole page. If it still fails, the error name on the page tells what to fix |
| F-55 | Moms file built from a page description only: no DTD, XSD or sample file was found on Skatteverket's pages, so the XML is not validated locally | Medium | Open (to be confirmed by a real upload) | The structure, element names, order, number rules and the ruta 49 formula follow the page "Lämna momsdeklaration via fil i e-tjänsten". Skatteverket checks the file at upload and the owner can correct before signing. Test with one real month first |
| F-56 | Notifications showed only a launcher badge on the owner's Galaxy S23 Ultra, nothing in the list or status bar | Medium | Mitigated, cause not confirmed (to be checked on the phone) | New channel `betalningar_v2` with high importance, a white status-bar symbol instead of the coloured launcher icon, and a temporary test notification (now and in one minute) to tell whether the cause is the icon, the importance or Samsung's battery settings |
| F-57 | A payment split in parts stores the main method in `pay_method` too; code that reads only `payMethod` would miss the split | Low | Open | All places that book, sum or match payments use `Invoice.parts` or `bankPart`. Any new code must do the same |
| F-58 | Bank matching of card deposits is a heuristic (fee up to 6 %, runs of up to seven days) and can match the wrong run | Medium | Open (to be checked with a real bank file) | A match is shown with the Z-report days and the fee so the owner can see it; "Kolla" lines say what may be wrong; nothing is booked from it |
| DOC-5 | User guide print booklet (A6) | Rebuilt from the guide each time; pages were not re-inspected after the last text edits | Low | Open |
| DOC-6 | Download card and packaging files | Not changed in this period; not re-inspected | Low | Not reviewed |
| DOC-7 | These project documents (01–07) | New; first baseline | – | For owner review |

## 4. Review checklists used

**UX heuristics (applied to each main screen):** visibility of status; match with the owner's words; user control and undo; consistency; error prevention; recognition over recall; minimal clutter; helpful errors; empty states; accessibility (contrast, size, targets, screen reader).

**Code:** dependency direction (ui → app → data → domain); money as integer öre; no money in floating point; errors handled and not swallowed; no hard-coded secrets; no network use without consent; tests exist for rules that touch money.

**Security:** where data lives; what leaves the device and why; secrets storage; lock behaviour; backup encryption; permissions; update and signing.

**Documents:** correct against the code; dated; owner named; open points marked; no private data.

## 5. Summary of open items

- **High:** F-26 (database upgrade untested).
- **Medium:** F-07, F-08, F-09, F-23, F-25, DOC-1, F-06 (root cause).
- **Low:** F-12, DOC-4, DOC-5, and the partly fixed items F-11, F-13, F-17.

## 6. Approval

| Role | Name | Date | Decision |
|---|---|---|---|
| Product owner | | | |
