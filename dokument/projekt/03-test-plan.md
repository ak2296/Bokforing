# 03 – Test plan

Baseline: release `v2026.11.13i`. Results are in [04-test-report.md](04-test-report.md).

## 1. Objectives

1. Money, moms and report figures are exactly right and stay right when code changes.
2. Documents are read correctly enough that the user only confirms or fixes a few fields; uncertain readings are flagged, never hidden.
3. Nothing is saved without confirmation; saved data is never silently changed.
4. Data survives updates, restores and device changes.
5. The app is usable on real phones: readable, reachable, fast enough.

## 2. Scope

**In scope:** everything in the requirements (01), the build pipeline, signing and update behaviour (07).
**Out of scope:** load or stress testing (single-user local app), server testing (there is no server), iOS (not built yet).

## 3. Test levels and approach

| Level | What | Tool | Where it runs |
|---|---|---|---|
| Static analysis | Dart analyzer with `flutter_lints`; warnings fail the build | `flutter analyze` | CI on every push |
| Unit | Pure Dart rules: money, moms, dates, parsers, validation, reports, SIE, tax estimate, licence, bank matching | `flutter_test` | CI |
| Data | Repository and schema against a real SQLite (FFI) | `flutter_test` + `sqflite_common_ffi` | CI (SQLite installed on the runner) |
| Widget | A few screens and charts rendered in a test harness (overview in dark mode, report charts, biometric and PIN flows) | `flutter_test` | CI |
| Reader regression ("phone papers") | Text of real documents (anonymised, kept as strings) run through classifier and parsers; expected fields asserted | `flutter_test` | CI |
| Build verification | Debug and release APK build; signing certificate check | GitHub Actions | CI |
| Manual / device | Camera, crop, import, share-in, notifications, backup folder, biometrics, themes, layouts | Checklist (section 6) | Owner's phone |
| Update test | Install a new APK over the previous release; check data is intact | Checklist (section 7) | Owner's phone |

**Approach.** Rules that handle money or reading get an automated test before or with the change. Screens are checked by hand because the project has no emulator or device farm. Every reader failure found with a real document becomes a regression case ("phone papers") so it cannot return.

## 4. Test data

- Anonymised document texts embedded in tests (supplier names, org numbers and amounts only as needed; no private owner data).
- A fixed clock (`now` passed in) for date-dependent logic such as reminders and weekday averages.
- In-memory or temporary SQLite databases per test.
- The owner's real documents and bank file are **never** copied into the repository (project rule).

## 5. Environments

| Environment | Purpose |
|---|---|
| GitHub Actions (Linux runner) | Analysis, tests, builds. There is no local Flutter install on the development machine; CI is the only place tests run. |
| Owner's Android phone | Manual and update tests. |
| Second device or older Android version | **Not available yet** – see risk R-07. |

## 6. Manual test checklist (run before each customer release)

Mark each line Pass / Fail / N/A with the build number.

**Install and start**
- [ ] Fresh install from the QR page; "Tillåt från den här källan" flow works.
- [ ] Setup wizard completes; first-run tour shows and can be skipped; "Visa rundtur" repeats it.
- [ ] Activation code accepted; app works; Översikt shows the activation end date (red within 10 days).

**Scan and review**
- [ ] Camera: yellow frame, level bubble, "I delar" for a long receipt.
- [ ] Corner adjustment; "Ta om".
- [ ] Invoice: fields filled, orange fields flagged, edit, save; duplicate warning on second save.
- [ ] Receipt: no due date; counts on its date.
- [ ] Invoice with two moms rates: both rows shown; "Ingen moms" greys moms fields.
- [ ] Z-report: category mapping, difference warning, "Spara ändå".
- [ ] Payslip: all fields, cost appears under Löner and Sociala avgifter.
- [ ] Online sales statement incl. fee invoice follow-up.
- [ ] Importera fil: PDF and JPG; share-in from e-mail.
- [ ] Fyll i själv for each type.

**Lists and reports**
- [ ] Översikt cards: Säkerhetskopia (on/off), Att betala (normal, yellow in reminder window, red overdue), equal card heights.
- [ ] Utgifter: amounts red (overdue) and brown (unpaid), "Fyll i" chip right under the amount.
- [ ] Månad, År, Resultat, Jämför show matching numbers for the same period.
- [ ] Export PDF, Excel, print; month export contains every day.
- [ ] SIE file by e-mail and saved; imports in accounting software.
- [ ] Tax estimate lines for AB and for enskild firma (percent and yearly amount).
- [ ] Avrunda utgifter on and off.

**Data protection**
- [ ] PIN set, wrong PIN shakes and vibrates, wait after repeated mistakes, 2-minute grace.
- [ ] Fingerprint unlock; PIN still works.
- [ ] Automatic backup written; last backup time on Översikt; restore on a clean install.
- [ ] Reminder notification arrives at 09:00 before the due date.

**Look and feel**
- [ ] Light, dark and auto theme; no field unreadable in either; switching theme refreshes everything including the nav bar.
- [ ] Entry fields look editable (white, clear outline).
- [ ] Large system font size: no overflow in nav bar, cards or review pages.
- [ ] Bright sunlight: selected tab and orange text readable.
- [ ] Swipe between the four main tabs; Skanna and Rapporter inner tabs tap only.

## 7. Update test (before publishing a release)

1. Install the previous release and register at least one of each document type, a payslip, and set a PIN and backup.
2. Install the new APK over it without uninstalling.
3. Check: app opens, PIN works, all records present, reports unchanged, backup still active.
4. If the database version changed, also restore a backup made by the previous version.

## 8. Entry and exit criteria

**Entry (start testing a build):** the CI run for the commit is green (analysis, tests, both APKs, signing check).
**Exit (release to customers):** manual checklist has no open Fail on a Must requirement; update test passed; the release notes (07) list changes; no open High finding in the review record (05) that affects the change.

## 9. Defect handling

Defects found by hand are written as findings in 05 with a severity. A reader failure gets a regression test first, then a fix. A High defect blocks release; Medium and Low are scheduled.

## 10. Roles

| Role | Who |
|---|---|
| Test owner and approver | Product owner |
| Test author | Developer (Claude Code sessions under the owner's direction) |
| Executor of manual tests | Product owner on their phone |

## 11. Test improvements planned

See gaps G-1 to G-7 in the test report: a database upgrade test, a test for the counting-date rule, coverage measurement, more widget tests for review pages, and a second test device.
