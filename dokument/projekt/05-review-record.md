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
| F-27 | Build and release pipeline | – | Pass, with notes | Analysis and tests gate the build; signing certificate verified in CI with a fixed key. Notes: the signing key secret is a single point of failure (R-03); the build number has never been raised from 2 and CI does not set it (R-04) |

## 3. Document inspection

Each project document was compared with the code and the shipped behaviour.

| ID | Document | Finding | Sev. | Status |
|---|---|---|---|---|
| DOC-1 | `HANDOFF.md` | Out of date in places: describes database schema v1 (now v9), branch `ny-start`, and an early file layout; still correct on the owner's decisions and rules | Medium | Open |
| DOC-2 | `PRODUCT.md` | Current; written 2026-11-13; open decisions (pricing, accountant workflow) are marked | – | Pass |
| DOC-3 | `FUTURE_FUNCTIONS.md` | Current; lists parked company-only functions | – | Pass |
| DOC-4 | User guide (A5 PDF, version 1.3) | Updated for the changes up to the tour and tax estimate; the phone mock-up on the tab page still shows the old amber "Att betala" banner, not the new half-width cards | Low | Open |
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
