# Future functions

Possible additions to the app. Nothing here is built yet. The owner picks what comes next; when a function is finished it is removed from this list.

## Free functions

Built in the app only, with no running costs.

### 1. Balansrapport and analysis report
- Uses the company form and financial year already set under Inställningar → Företag.
- Needs figures the app does not have yet: bank balance, assets, loans and opening balances.
- Clearly marked as based only on what is registered in the app, not as an official balansräkning.

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
