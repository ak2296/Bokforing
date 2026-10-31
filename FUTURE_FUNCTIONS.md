# Future functions

Possible additions to the app. Nothing here is built yet. The owner picks what comes next; when a function is finished it is removed from this list.

## 1. App lock (licence per company)
- The buyer sends their company name and organisation number and gets a short activation code.
- Codes are created on a GitHub page with a secret key that only the owner has. The app only checks codes, offline, and cannot create them.
- After activation the company name and org number are locked and appear on every report and PDF. A copied APK without a code cannot save anything; with someone else's code it works only under that company's name.
- One build for all customers. No new build per company or code.
- Limit: without a server copying cannot be stopped completely, only made useless for ordinary users.

## 2. Simple resultatrapport (profit and loss)
- A cost type for each invoice (e.g. Varuinköp, Lokalhyra, El, Förbrukningsmaterial), suggested from the supplier and remembered.
- Monthly and yearly report: sales excl. VAT, costs excl. VAT per cost type, result.
- Clearly marked as based only on what is registered in the app.

## 3. SIE export to the accountant or bookkeeping program
- Export a period as an SIE 4 file (Swedish standard, read by Fortnox, Visma, Bokio and accountants).
- Each day's sales and each invoice become bookkeeping entries on BAS accounts (sales per VAT rate, input/output VAT, costs).
- The accountant's program then produces the official resultaträkning and balansräkning.

## 4. Paid / unpaid invoices (base for a balance view)
- Mark invoices as paid or unpaid, with payment date.
- List of unpaid invoices and amounts owed.
- Could later grow into a simple balance overview. A full balansrapport needs complete double-entry bookkeeping (bank, cash, loans, assets, equity) and is a much larger project.
