# Future functions

Possible additions to the app. Nothing here is built yet. The owner picks what comes next; when a function is finished it is removed from this list.

## Free functions

Built in the app only, with no running costs.

### 1. Balansrapport and analysis report
- Uses the company form and financial year already set under Inställningar → Företag.
- Needs figures the app does not have yet: bank balance, assets, loans and opening balances.
- Clearly marked as based only on what is registered in the app, not as an official balansräkning.

### 4. Electronic personalliggare (staff register)
- Restaurants must keep a personalliggare, on paper or electronic ([Skatteverket](https://www.skatteverket.se/foretag/etjansterochblanketter/svarpavanligafragor/personalliggare/foretagpersonalliggarefaq/vadinnebarenelektroniskpersonalliggareochvilkakravskadenuppfylla.5.7da1d2e118be03f8e4f5c74.html)).
- In the app: a staff list (name and personnummer or samordningsnummer), check in and check out with the time, per restaurant premises.
- A tamper-evident log: every change shows who made it and when, and nothing can be changed afterwards without a trace. The app already has an audit log to build on.
- Export and print for a Skatteverket inspection. Works offline.
- Rules to meet: Skatteverket must be able to review the entries back in time, the register must be available on the premises at an inspection, and it is kept for two years after the calendar year in which the tax year ended.
- The software rules are in 9 kap 5 § skatteförfarandeförordningen and SKVFS 2015:6. No approval process and no list of approved systems was found for restaurants.
- Open points to check with Skatteverket first: that a phone app is accepted, how to show the register if the phone is not on site, and the privacy of personnummer.

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
