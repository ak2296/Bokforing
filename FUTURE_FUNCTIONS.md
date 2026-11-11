# Future functions

Possible additions to the app. Nothing here is built yet. The owner picks what comes next; when a function is finished it is removed from this list. The numbers are only labels.

## Free functions

Built in the app only, with no running costs and no company needed.

### 1. Balansrapport and analysis report
- Uses the company form and financial year already set under Inställningar → Företag.
- Needs figures the app does not have yet: bank balance, assets, loans and opening balances.
- Clearly marked as based only on what is registered in the app, not as an official balansräkning.

### 5. Månadslås and correcting entries
- "Stäng månaden" locks a month after the moms is filed: no editing or deleting in it.
- A mistake found later is fixed with a new correcting record in the open month, with who and when; the old record stays visible.
- Basis: BFNAR 2013:2 (a computerised entry is corrected with a separate correcting entry that has its own verifikation, and a closed period is not corrected into).
- Not clear from the sources: when a saved record counts as "booked". Ask an accountant.

### 6. Moms file for Skatteverket
- The app builds the XML file (`eSKDUpload`, version 6.0, ISO-8859-1) and shows the same figures as rutor 05, 10–12, 48 and 49. The owner uploads it in Skatteverket's e-service "Lämna momsdeklaration" and signs there with e-legitimation. No agreement with Skatteverket is needed.
- Amounts are whole kronor. How to round the sums is not confirmed (older forms say "endast kronor"); ask an accountant once.
- Leave the optional text field empty (the allowed characters are unclear).

### 7. Bank file import and matching
- The user exports transactions from the internet bank as CSV or Excel; the app matches payments to invoices (marks them paid) and Swish/card deposits to Z-reports, and lists what is unmatched. Nothing leaves the phone.
- Layout seen in a Swedbank "Transaktioner" export from a private account: a title line starting with `*`, then a header row; 12 comma-separated columns (Radnummer, Clearingnummer, Kontonummer, Produkt, Valuta, Bokföringsdag, Transaktionsdag, Valutadag, Referens, Beskrivning, Belopp, Bokfört saldo); Windows-1252 text, not UTF-8; dates as yyyy-mm-dd; dot as decimal point and no thousands separator; outgoing amounts negative; newest row first; each row's saldo equals the saldo of the row below plus its own amount, so the import can detect missing rows.
- A business account's export may have other columns. Read columns by their header names, keep a few known presets, and get a business-account sample before relying on it.
- Test files must be made up. A real bank file is never copied into the code, tests or git.

### 8. Checklist before closing a month
- A read-only list with a link to each problem: invoices with "Fyll i", Z-reports with a difference or missing days, possible duplicates, doubtful moms.

### 9. App lock with PIN
- A PIN (and fingerprint if the phone has it) to open the app, asked again after the app has been in the background for a set time. Too many wrong tries slow down further tries.
- The backup password is a different thing: it encrypts the backup file, which can leave the phone. A short PIN could be cracked offline, so the backup keeps a real password (8 characters or more). The PIN can still be asked before making or restoring a backup.
- Needs a way back if the PIN is forgotten, for example the backup password.

### 10. Verifikationslista and "Förhandsvisa SIE"
- Shows the verifikationer the SIE file will contain (number, date, account, debit, credit) before it is sent to the redovisare. Low priority if the owner only sends the file.

## Outside bookkeeping (maybe never)

### 4. Electronic personalliggare (staff register)
- Not bookkeeping: it is a staff register Skatteverket requires restaurants to keep, on paper or electronic. Most restaurants keep a paper book.
- The owner is responsible but does not have to write the entries. Each person is entered when the shift starts and ends, directly, never in advance. If only the owner, spouse and children under 16 work there, no register is needed.
- If ever built, the staff would check in themselves, for example on a shared tablet at the entrance, not the owner on his own phone.
- A software register must log who changed what and when, let Skatteverket review entries back in time, be available on the premises at an inspection, and be kept for two years after the calendar year in which the tax year ended. The rules are in 9 kap 5 § skatteförfarandeförordningen and SKVFS 2015:6; no approval process or list of approved systems was found for restaurants.

## Needs a registered company (not possible for now)

The owner has no company yet. Our rules for each, from Skatteverket's and Bolagsverket's pages:

### 11. Skatteverket's moms API
- Lets the app prepare the moms return directly in Skatteverket's service; signing still happens at Skatteverket with e-legitimation.
- The software company must have F-skatt, be registered for moms, and have no unpaid tax debt at Kronofogden (and be registered as an employer where that applies). Individual developers are not mentioned.
- Free of charge; each side bears its own costs. Apply with the form "Begär tillgång till våra API:er". The test service needs only the form. Production needs an agreement signed on Mina sidor and countersigned by Skatteverket. Processing is slow.
- Until then, function 6 (the XML file) does the job.

### 12. Payroll and AGI
- Skatteverket has a file upload and an API for AGI; the API uses the same kind of agreement as the moms API.
- Payroll rules are large and risky. Better to read lönespecifikationer and record the cost than to calculate payroll.

### 13. Bolagsverket's digital årsredovisning
- Bolagsverket takes iXBRL files through software vendors it lists, for AB under K2. Big and risky; leave to the accountant.

### 14. Live bank connection for customers
- See function 3. Enable Banking is free in its test environment and for the developer's own accounts; use for customers needs an agreement and a price per connected account and month. Payment initiation needs a licence (PISP).

## Paid functions

Need an outside service with fees, a contract or both.

### 2. Google Play and subscriptions
- Publish the app on Google Play and let Google charge and renew subscriptions, replacing the codes sent by hand.
- Costs: a one-time Google developer fee, and Google keeps a share of each subscription.

### 3. Bank connection and paying fakturor in the app
- Pay an unpaid faktura from the app: bankgiro/plusgiro, OCR and amount, as already read from the paper, are sent to the bank and approved with BankID.
- Needs a licensed partner for payment initiation under PSD2 (for example Tink, Enable Banking or Open Payments); building it without one means a licence from Finansinspektionen.
- Needs a small server of our own for the partner's secret keys (never stored in the app) and internet access in the app.
- Costs: the partner's monthly fee and a fee per payment, plus a contract and a company check.
- About a few weeks of work once the partner contract is in place.
- A free middle step is possible first: a "Betala" button that copies the payment details or shows them as a QR code for the bank app.
