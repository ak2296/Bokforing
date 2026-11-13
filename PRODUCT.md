# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Users

Small business owners in Sweden, who are not accountants and do their own day-to-day bookkeeping on a phone. The first customer type is the restaurant or pub owner, but the product is not limited to restaurants. They scan or enter invoices, receipts, daily Z-reports from the cash register, online-sales statements and payslips, between other work, and hand the result to an external redovisare (accountant) as reports and a SIE file.

## Product Purpose

Quee turns paper and PDF bookkeeping documents into checked records, monthly and yearly reports, moms figures and a SIE file for the accountant. Success: most of the bookkeeping work is already done when it reaches the accountant, so the owner spends less time on it and, over time, pays the accountant less.

## Positioning

- Does most of the bookkeeping work on the phone: scan, read, check, save, report.
- Everything stays on the phone. A local database, no account, no login; nothing leaves the device unless the owner chooses it (backup, optional online reading).
- Scan, check, then save: nothing is saved before the user confirms, uncertain readings are flagged, and the app never silently changes a printed amount.
- Made for Swedish small business: Swedish moms rates, Z-reports, Swedish invoice and payslip formats, förfallodatum as the day an expense counts, SIE export. All UI text is Swedish.

## Operating Context

- Phone use while running a business: restaurant, shop floor, a desk at the end of the day. Papers are photographed, imported as PDF/images, or shared in from e-mail.
- The owner's reports, moms and SIE file go to an external redovisare. The app's totals are estimates from what is registered in the app, not a moms return or official bookkeeping.
- Money is stored as integer öre. A record's expense date is its förfallodatum when it has one, otherwise its own date (receipts).
- Sold directly, not through Google Play: installed from an APK behind a QR card, activated with a per-customer code that is checked offline.

## Capabilities and Constraints

- Scanning with automatic type detection (faktura/kvitto, Z-report, online sales, payslip), crop, OCR, manual entry, file import and share-in from other apps.
- Reports: monthly, yearly, result with cost types, comparison; PDF, Excel, print; SIE file; estimated tax to set aside (aktiebolag 20,6 %, enskild firma by the owner's own percentage or yearly amount).
- Overview, unpaid invoices with reminders, bank-file payment matching, learning of where a supplier prints each field (from the user's corrections), automatic encrypted backup, PIN and fingerprint lock, light and dark theme, first-run tour, user guide (A5 PDF and A6 print booklet).
- No company exists yet. Features that only make sense with a company (closing a month, filing a moms return, and similar) are parked in `FUTURE_FUNCTIONS.md`.
- Android now, iOS later: keep code portable but build and test on Android only for now. The app is built with Flutter; there is no local Flutter install, so builds are verified on GitHub CI.
- The owner's own bank CSV and data are private: learn layouts only, never copy real data into the repository.
- Undecided: pricing, the accountant-side workflow, and which company-only features come first.

## Brand Commitments

- Name: Quee.
- All user-facing text is Swedish, in plain words a non-accountant understands. Estimates are labelled as estimates.

## Evidence on Hand

- User guide, A5 and A6 booklet: `dokument/anvandarguide/`; download card: `dokument/kort/`; packaging: `dokument/forpackning/`.
- Releases are published to the download repo `ak2296/quee` as `Quee.apk` after each green build.
- Absent and not to be invented: customer testimonials, named customers, pricing, benchmarks, usage numbers, accountant endorsements.

## Product Principles

1. Check before save. The user confirms every record; uncertainty is shown, never hidden.
2. Private by default. Data stays on the phone unless the owner chooses otherwise.
3. Plain Swedish for non-accountants. Name things as the owner would, and label every calculation that is only an estimate.
4. Fewer steps toward the redovisare. Prefer anything that makes the data complete and correct before it reaches the accountant.
5. Never invent a number. Totals derive from registered records and are never stored separately.

## Accessibility & Inclusion

Used in working environments such as a restaurant, so text and states must be readable in bright and dim light; light and dark themes are both first-class. The phone's font-size setting should not break layouts. No formal standard has been chosen yet.
