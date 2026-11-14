# 01 – Requirements and user stories

Baseline: release 2026.11.13 (`v2026.11.13i`), database version 9.

## 1. Purpose and scope

Quee turns paper and PDF bookkeeping documents into checked records, reports, moms figures and a SIE file for the owner's redovisare (accountant). Success means most of the bookkeeping work is already done when it reaches the accountant.

**In scope:** invoices and receipts, daily Z-reports from the cash register, online-sales statements, payslips (lönebesked), monthly/yearly/result/comparison reports, moms estimates, SIE export, bank-file payment matching, payment reminders, backup, lock, user guide.

**Out of scope (see `FUTURE_FUNCTIONS.md`):** filing a moms return, closing a month, payroll/AGI, balance sheet, anything that needs a company or a server. The app never replaces official bookkeeping or a moms return.

## 2. Users

| User | Description | Needs |
|---|---|---|
| Owner | Small business owner in Sweden, not an accountant. First customer type: restaurant or pub. | Register documents quickly on the phone, see sales, costs and moms, hand clean data to the accountant. |
| Accountant (redovisare) | External, receives reports and a SIE file. Does not use the app. | Complete, correct, importable data. |
| Seller/distributor | Gives customers the APK, a QR card and an activation code. | Simple install, per-customer activation, no store dependency. |

## 3. Constraints

- **C-1** Android now, iPhone later: code stays portable; only Android is built and tested.
- **C-2** No server and no account. All data is stored on the phone.
- **C-3** All user-facing text is Swedish. Money in SEK with Swedish format (`1 250,50 kr`), dates `ÅÅÅÅ-MM-DD`.
- **C-4** Money is stored as integer öre everywhere; floating point is never used for money.
- **C-5** Nothing is saved before the user confirms ("Godkänn och spara").
- **C-6** Distribution outside Google Play: APK behind a QR card, activation checked offline.
- **C-7** VAT is never assigned from a category name; the user picks the rate per category.

## 4. Functional requirements

Priority: **M** must, **S** should, **C** could. "Verified by" names automated test files in `test/`; **Manual** means it is covered by the manual checklist in the test plan (03).

### 4.1 Capture and reading

| ID | Requirement | Pri | Verified by |
|---|---|---|---|
| FR-01 | The user can photograph a document with the camera, with edge detection, tilt hint and a "whole / in parts" mode for long receipts. | M | Manual |
| FR-02 | The user can adjust the four corners of a scanned document; content outside the frame is dropped and the page is straightened. | M | Manual; `imaging_merge_test` (image merge) |
| FR-03 | The user can import a PDF or image file, or share one into the app from another app (for example an e-mail attachment). | M | Manual |
| FR-04 | The app reads text on the device (OCR) and detects the document type: invoice/receipt, Z-report, online sales, payslip. | M | `parsers_test`, `phone_papers*_test`, `payslip_test` |
| FR-05 | For an invoice the app extracts date, supplier, invoice number, total (att betala), moms per rate, due date, OCR reference, bankgiro and plusgiro. The total is never chosen as "the largest number". | M | `parsers_test`, `phone_papers*_test`, `willys_test` |
| FR-06 | For a Z-report the app extracts the business date, sales per category and the total; it does not force the sum to match and shows any difference. | M | `z_layout_test`, `z_fields_test`, `parsers_test` |
| FR-07 | For a payslip the app extracts employee, personnummer, payout date, period, bruttolön, arbetsgivaravgift and preliminär skatt. | M | `payslip_test`, `payslip_records_test` |
| FR-08 | Online-sales statements (for example Foodora) are read; if the paper also carries the partner's fee invoice, the app registers the sale first and then opens the fee invoice as an expense. | S | `online_vat_test`, `phone_papers*_test` |
| FR-09 | The user can enter any document type manually without a scan. | M | Manual |
| FR-10 | Optionally, a second reading can be done online (Google Gemini) with the user's own API key. It is off by default, asks every time, and its result passes the same validation. | C | `ai_result_test` |

### 4.2 Check and save

| ID | Requirement | Pri | Verified by |
|---|---|---|---|
| FR-11 | Every extracted value is shown with a confidence marker; values that need a check are flagged (one orange level). | M | Manual |
| FR-12 | The user reviews and edits every field before saving; nothing is saved without confirmation. | M | `repository_test` (save path); Manual |
| FR-13 | Validation checks that net + moms equals the total and that moms per rate matches the total moms; a mismatch is shown, never silently corrected. | M | `validation_reports_test`, `money_vat_test` |
| FR-14 | The app warns about probable duplicates (same OCR number, same supplier and number, same date and amount, same amount within 10 days) and offers "Visa befintlig" or "Registrera ändå". | M | `hints_duplicates_test` |
| FR-15 | An invoice can be marked as a credit note; amounts become negative and reduce costs and input moms. | M | `repository_test`, `validation_reports_test` |
| FR-16 | An invoice can be marked "Ingen moms"; the moms fields become inactive, and a 0 % row is stored. | M | `search_incomplete_test` |
| FR-17 | An invoice with several moms rates shows one row per rate; with one rate no duplicate amount is shown. | M | Manual |
| FR-18 | Each invoice has a cost type (for example Varuinköp, Lokalhyra, El, Säkerhet). The app suggests the type per supplier. | M | `report_fixes_test`, `month_export_test` |
| FR-19 | An expense counts on its due date (förfallodatum); if it has none (receipt) it counts on its own date. | M | Manual. No automated test of `Invoice.bookingDate` yet (gap G-1 in 04). |
| FR-20 | Paid status is suggested (receipt, card payment, stamp BETALD) and confirmed by the user; unpaid invoices appear under "Att betala". | M | `payments_test` |
| FR-21 | A payslip is a record of its own; its cost (bruttolön and arbetsgivaravgift, no moms) appears in expenses, reports and SIE on the payout date. | M | `payslip_records_test` |
| FR-22 | The app learns, from the user's corrections, the printed label that precedes a value for a supplier, and reads that label first next time. It never stores values. | S | `hints_duplicates_test` |
| FR-23 | Records can be edited and deleted (after confirmation); every create, update, delete and payment change is written to an audit log. | M | `repository_test` |
| FR-24 | The user can see the original image and the read text of a saved record. | S | Manual |

### 4.3 Overview, lists and reports

| ID | Requirement | Pri | Verified by |
|---|---|---|---|
| FR-25 | Översikt shows the month's sales and expenses compared with the previous month, a six-month chart, weekday averages, calculated moms, the five latest registrations, a backup card, an "Att betala" card with the next due date, and when the activation ends. | M | `overview_dark_test`, `comparison_test` |
| FR-26 | Försäljning and Utgifter list a month at a time with totals, share bars, search and filters; incomplete invoices are marked "Fyll i". | M | `search_incomplete_test` |
| FR-27 | Månad report: one row per day with sales per category, expenses and moms; empty days are hidden in the app but always present in PDF, Excel and print. | M | `month_export_test`, `export_test` |
| FR-28 | År report: every month with sales, online, expenses, output and input moms, moms difference, and a card with the year's result and moms. | M | `report_charts_test`, `export_test` |
| FR-29 | Resultat report: income, costs per cost type and result, without moms, for a month or a financial year, with a waterfall chart and a cost-share view. | M | `result_charts_test`, `result_sie_test` |
| FR-30 | Jämför compares two years month by month with percentage change. | S | `comparison_test` |
| FR-31 | Månad and År show an estimated tax to set aside: 20,6 % for aktiebolag; for enskild firma the owner's own percentage or yearly amount. Labelled as an estimate. | S | `tax_estimate_test` |
| FR-32 | Reports can be exported as PDF, Excel/CSV and printed. | M | `export_test` |
| FR-33 | "Avrunda utgifter" shows costs in whole kronor (half up) in lists and reports without changing saved amounts. | S | `avrundning_test` |
| FR-34 | A SIE file (type 4) for a period can be sent by e-mail or saved; verifikationer for invoices, payments, Z-reports and payslips (series D). | M | `result_sie_test` |
| FR-35 | Moms is shown as "beräknad" and is never presented as a moms return. | M | Manual |

### 4.4 Payments and reminders

| ID | Requirement | Pri | Verified by |
|---|---|---|---|
| FR-36 | A bank CSV file can be matched against unpaid invoices (exact amount); the user confirms every match; the file is not stored. | S | `bank_import_test` |
| FR-37 | Reminders are shown before and on the due date, with a lead time the user sets. | S | `payments_test` (reminder times); notification display is Manual |

### 4.5 Data protection and administration

| ID | Requirement | Pri | Verified by |
|---|---|---|---|
| FR-38 | The app can be locked with a 4–6 digit PIN, with growing waits after wrong attempts and a 2-minute grace after leaving the app. | M | `pin_lock_test` |
| FR-39 | Fingerprint unlock is optional; the PIN always remains as fallback. | S | `biometric_lock_test` |
| FR-40 | A wrong PIN shakes the dots and vibrates. | C | Manual |
| FR-41 | Automatic encrypted backup to a folder chosen by the user, after each change (at most one per day, last three kept), with a password the user writes down. | M | `export_test`, `storage_test` |
| FR-42 | A backup can be sent to a cloud service through the share menu and restored on a new phone (also from the first screen). | M | `export_test` |
| FR-43 | The app is activated with an offline-verifiable code (signature check); without activation records can be viewed but not created. | M | `license_test` |
| FR-44 | The first-run wizard sets company name, form, categories with moms, and Z-report line rules. | M | Manual |
| FR-45 | Settings are grouped, searchable, and include theme (Auto, Ljust, Mörkt), rounding, reminders, learned fields, storage and the user guide. | M | Manual |
| FR-46 | A first-run tour highlights the main parts of the app and can be shown again. | C | Manual |
| FR-47 | Company names, categories and own company names are editable; the company's own name is never used as supplier. | M | `own_company_test` |
| FR-49 | Any scan whose first reading has doubts (a key field missing or uncertain, rows that do not add up) on a tilted photo is read a second time with the photo turned by the measured tilt; the better reading is kept. The waiting screen shows a progress bar and the step. Applies to invoices, Z-reports, online sales and payslips. | S | `z_layout_test`, `reading_doubts_test` (doubt counts); the second reading itself: Manual |
| FR-50 | Before the SIE file is sent, the owner can open "Förhandsvisa SIE" and see every verification the file will hold: series and number, date, text, each account with debit and credit, a balance check per verification and in total. The lines are the ones the file is built from. | S | `result_sie_test`, `sie_preview_test` |
| FR-48 | The app looks for a newer release once a day (switch in Inställningar), shows a card on Översikt, and on request downloads the APK and hands it to Android's installer; data is kept. Off in a Google Play build. | S | `app_update_test` (release parsing, download); installer step Manual |

## 5. Non-functional requirements

| ID | Requirement | Verified by |
|---|---|---|
| NFR-01 | **Accuracy:** money calculations are exact (integer öre); moms is computed as `gross × r / (100 + r)` with rates in basis points; rounding rules are fixed and tested. | `money_vat_test` |
| NFR-02 | **Privacy:** no analytics, no ads, no network use unless the user turns on online analysis, a backup share or similar. Data and backups are encrypted at rest where stored by the app. | Review F-14; Manual |
| NFR-03 | **Offline:** every core function works without internet, including activation checks. | Manual |
| NFR-04 | **Traceability:** every record keeps source (scan, manual, online), whether it was edited, and an audit history. | `repository_test` |
| NFR-05 | **Usability:** layouts must work with the phone's font-size setting and in bright and dim light; both light and dark themes are first-class; touch targets at least 48 dp. | Review F-07, F-08 (open) |
| NFR-06 | **Data safety on update:** an APK update keeps all data; the database upgrades from any older version. | `repository_test`; gap G-3 in 04 |
| NFR-07 | **Performance:** scanning to review screen should feel immediate on a mid-range phone. | Not measured |
| NFR-08 | **Maintainability:** analysis has no warnings and all tests pass before a release; CI enforces both. | CI |
| NFR-09 | **Portability:** domain logic is plain Dart with no platform dependency. | Review F-16 |

## 6. User stories and acceptance criteria

**US-01 – Register a supplier invoice.** *As an owner, I want to photograph an invoice and check what the app read, so I do not have to type it.*
Acceptance: given a clear photo, when I tap Skanna, the app opens a review with date, supplier, total, moms and due date filled in; fields it is unsure about are orange; I can change any field; saving is only possible after I tap "Godkänn och spara"; the invoice then appears in Utgifter on its due date.

**US-02 – Register the day's sales.** *As an owner, I want to scan the Z-report, so the day's sales are in the books.*
Acceptance: the business date comes from the report; each line is shown with the category and moms rate it counts as; a total that differs from the report's total is shown with "Ändra belopp", "Skanna igen" or "Spara ändå".

**US-03 – Know what to pay.** *As an owner, I want to see unpaid invoices, so I pay on time.*
Acceptance: Översikt and Utgifter show count, sum, number overdue and the next due date; the card is yellow inside my reminder period and red when something is overdue.

**US-04 – Give the accountant clean data.** *As an owner, I want one file for my accountant, so they do not retype anything.*
Acceptance: Resultat offers "SIE-fil till redovisaren" by e-mail or save; the file contains verifikationer for the period and imports without errors in common accounting software.

**US-05 – Understand the month.** *As an owner, I want a monthly report and a yearly overview, so I see how the business does.*
Acceptance: Månad shows one row per day and totals; År shows each month; both show result before and after estimated tax and calculated moms, clearly labelled as estimates.

**US-06 – Pay salary correctly.** *As an owner, I want to register a payslip, so wages count as a cost.*
Acceptance: employee, payout date, bruttolön, arbetsgivaravgift and preliminär skatt are stored; cost appears as Löner and Sociala avgifter on the payout date; no moms is calculated.

**US-07 – Keep data safe.** *As an owner, I want my data protected and backed up, so a lost phone does not lose my books.*
Acceptance: I can set a PIN and fingerprint; automatic backup writes an encrypted file to my chosen folder; the app warns on Översikt when automatic backup is off and shows the last backup time; I can restore on a new phone.

**US-08 – Start without help.** *As a new customer, I want a guided start, so I know what to do first.*
Acceptance: after the setup wizard a tour points out Översikt, Skanna, Försäljning, Utgifter, Rapporter and Inställningar; an empty Översikt tells me to scan my first document.

**US-09 – Correct a mistake.** *As an owner, I want to fix or remove a wrong record, so reports are right.*
Acceptance: I can edit or delete a record after confirmation; the change is listed in its history.

**US-10 – Match bank payments.** *As an owner, I want to match my bank file with unpaid invoices, so I do not mark each one by hand.*
Acceptance: the app proposes matches with exactly equal amounts; nothing changes until I confirm; the file is not kept.

## 7. Traceability summary

All "Must" requirements have either an automated test or a manual checklist item in the test plan (03). Requirements with only manual verification: FR-01, FR-02, FR-03, FR-09, FR-11, FR-17, FR-19, FR-24, FR-35, FR-44, FR-45, FR-46. NFR-07 is not measured. See 04 for the gaps this implies.
