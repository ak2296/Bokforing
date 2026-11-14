# 04 – Test report

Release under test: `v2026.11.13i` (commit `8204b71`, 2026-11-13).

## 1. Summary

| Item | Result |
|---|---|
| CI run for `8204b71` | Passed: analysis, tests, debug and release APK, signing check |
| Automated test files | 37 on CI at `8204b71`; 2 more written since (`app_update_test`, `reading_doubts_test`) plus new cases in `z_layout_test`, **not yet run on CI** |
| Automated test cases | About 319 (counted from `test(` and `testWidgets(` calls; parametrised cases are counted once) |
| Test code size | About 4 700 lines (library code about 21 000 lines) |
| Code coverage | **Not measured** |
| Manual checklist (03 §6) | **Not executed as a formal run for this release.** Individual features were seen on the owner's phone during development (screenshots), see §4. |
| Update test (03 §7) | **Not executed as a formal run** for this release. Earlier releases were installed over each other by the owner without reported data loss. |

**Judgement.** The money, parsing, report and data rules are well covered by automated tests. Screens and device behaviour are covered by hand only. The release is suitable for the owner's own use; before wider customer rollout, close gaps G-1, G-3 and G-6 and run the manual checklist.

## 2. Environment

- CI: GitHub Actions on Linux with SQLite installed for database tests; Flutter stable; Java for Gradle. There is no Flutter installation on the development machine, so tests cannot be run locally.
- Manual: the owner's Android phone, light and dark theme.

## 3. Automated tests by area

| Area | Test files (cases) | What they check |
|---|---|---|
| Money, moms, dates | `money_vat_test` (13) | Swedish parse/format, integer öre, moms from a gross amount, rounding, rate rules |
| Reading invoices and receipts | `parsers_test` (23), `phone_papers_test` (14), `phone_papers2_test` (8), `phone_papers3_test` (13), `phone_papers4_test` (24), `phone_papers5_test` (22), `phone_papers6_test` (9), `willys_test` (2) | Document type, total candidates, moms per rate, dates, due date, supplier, own-company handling, cash/change/card, regression for each real layout seen |
| Reading Z-reports | `z_layout_test` (3), `z_fields_test` (6) | Layout and category/label rules |
| Payslips | `payslip_test` (13), `payslip_records_test` (12) | Reading, records, expenses, SIE, backup, rounding |
| Online sales | `online_vat_test` (7) | Partner statements, self-invoice moms, fee invoice |
| Validation and reports | `validation_reports_test` (12), `report_fixes_test` (17), `month_export_test` (5), `comparison_test` (6), `report_charts_test` (1), `result_charts_test` (3), `result_sie_test` (2), `export_test` (2), `tax_estimate_test` (4) | Net + moms checks, report totals, every-day export, year comparison, charts, SIE, estimated tax |
| Data and repository | `repository_test` (5), `hints_duplicates_test` (5), `search_incomplete_test` (10), `payments_test` (7), `storage_test` (5), `avrundning_test` (5) | Save and load, duplicates, learned labels, search and incomplete invoices, paid/unpaid and reminder times, storage, rounding setting |
| Bank file | `bank_import_test` (12) | CSV layouts and amount matching |
| Security | `pin_lock_test` (8), `biometric_lock_test` (6), `license_test` (10) | PIN waits and grace, biometric flow with a fake, signed activation codes |
| Other | `own_company_test` (10), `imaging_merge_test` (5), `ai_result_test` (5), `overview_dark_test` (5) | Own names, image merge, AI result parsing, overview in dark mode |

## 4. Manual observations so far

Seen on the owner's phone during development (screenshots on file with the owner). These are observations, not a formal run:

- Lönebesked review in dark and light mode; date fields, unreadable warning fields and look of entry fields were found and fixed (F-01, F-02, F-03).
- Översikt after the card changes; unequal card heights found and fixed (F-04).
- Fingerprint unlock confirmed working by the owner.
- **In-app update (2026-11-14):** from a build without the fix to release `v2026.11.14` (build 29910225) with "Hämta och installera"; the owner reported that everything worked and the data was intact. This is a first real update test of the update path, not the full checklist.
- Floating navigation bar and spotlight confirmed by the owner after several iterations.

Not yet seen on a phone: the first-run tour, thousands separators in fields, the latest tax estimate cards, "Importera fil" after the error handling change.

## 5. Defects found in this period

| ID | Defect | Found by | Status |
|---|---|---|---|
| F-01 | Warning and "Osäker" fields unreadable in dark mode | Owner screenshots | Fixed in 5b4ad2a |
| F-02 | Dates cut off in half-width fields | Owner screenshots | Fixed (stacked fields) |
| F-03 | Text fields looked inactive (no fill) | Owner screenshots | Fixed in 3e28517 |
| F-04 | Cards in a row had unequal height | Owner screenshot | Fixed in 6ea5585 |
| F-05 | Scan button hidden under the floating bar | Owner | Fixed in 2d293f2 |
| F-06 | "Importera fil" raised an error once | Owner | Error handling added; root cause **not found** (message not captured) |

The full list of findings, including those not yet fixed, is in 05.

## 6. Gaps in testing

| ID | Gap | Impact | Plan |
|---|---|---|---|
| G-1 | No test for `Invoice.bookingDate` (due date counts, else invoice date) or for lists and reports using it | The core dating rule could regress unnoticed | Add unit tests for the rule and one report test |
| G-2 | Code coverage is not measured | Unknown blind spots | Add `flutter test --coverage` in CI and publish the number |
| G-3 | No test that opens an old-version database and upgrades it to version 9 | Customers who skip versions could lose data | Add an upgrade test per schema step with sample old files |
| G-4 | Only a handful of widget tests; review pages, Översikt cards and settings are untested | UI regressions are found by hand | Add widget tests for review pages and cards |
| G-5 | No device test for camera, crop, share-in, notifications, backup folder | Platform integration failures show only on the phone | Keep the manual checklist; consider an integration test run on an emulator in CI |
| G-6 | No second device, no older Android version, no tablet | Layout and permission differences unknown | Test on at least one more phone before wider rollout |
| G-7 | No accessibility test (TalkBack, large fonts, contrast) | See F-07, F-08 | Add to the checklist and run once |
| G-8 | Performance is not measured (OCR time, large databases) | Slowdowns found late | Measure scan time and open time with 12 months of data |

## 7. Conclusion and sign-off

The automated suite is a strong base for the numbers and reading rules. Release to customers should wait for the manual checklist run, G-1, G-3 and the accessibility findings F-07 and F-08.

| Role | Name | Date | Decision |
|---|---|---|---|
| Product owner | | | |
