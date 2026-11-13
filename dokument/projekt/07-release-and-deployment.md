# 07 – Release and deployment notes

Baseline: `v2026.11.13i`, commit `8204b71`.

## 1. Deployment model

Quee is an Android app on the customer's phone. There is **no server**, so there is nothing to deploy to a cluster and no need for blue-green or canary server deployments. A release is a signed APK that the customer installs over the old one.

| Item | Value |
|---|---|
| Source repository | `ak2296/Bokforing` (public) |
| Download repository | `ak2296/quee` – release APKs and the download page (`quee-main/index.html`) |
| Download link | `https://github.com/ak2296/quee/releases/latest/download/Quee.apk` |
| Release file | `Quee.apk` only (release build, no debug build) |
| Version in `pubspec.yaml` | `0.2.0+2`; CI overrides the build number with the minutes since 1970 (`--build-number`) and passes it to the app (`--dart-define=BUILD_NUMBER`). Not yet in a published release. |
| Database version | 9 |
| Minimum Android | 7.0 (as stated in the user guide) |

## 2. Build pipeline (GitHub Actions: "Bygg Android-APK")

1. Free disk space on the runner.
2. Check out the code; set up Java and Flutter.
3. Create the Android platform folders if missing (`flutter create`); copy the app icon.
4. Patch the generated Android settings: biometric support (FlutterFragmentActivity, AppCompat theme parents, `USE_BIOMETRIC`), no auto-backup, INTERNET only for the optional online reading, fixed signing configuration.
5. Decode the fixed signing key from repository secrets.
6. Install SQLite for the database tests; `flutter pub get`.
7. **Analysis** – warnings and errors fail the build.
8. **Tests** – any failure fails the build.
9. Build the debug and the release APK (release without shrinking).
10. **Check the signing** – both APKs must carry the fixed certificate or the run fails.
11. Upload the artifact `bokforing-apk` with `app-release.apk` and `app-debug.apk`.

A run takes about 11 minutes. There is no local Flutter install; CI is the only place tests and builds run.

## 3. How a release is made

Rule from the owner: **nothing is pushed or published before the owner confirms.**

1. Make the changes locally and update the user guide if behaviour changed (`py dokument/verktyg/make_docs.py` rebuilds the guide PDFs and copies the guide into `assets/`).
2. Owner confirms the push. Push to `main`.
3. Wait for the CI run to pass. If it fails, read the failed log, fix, push again.
4. Download the artifact `bokforing-apk`; copy `app-release.apk` to `Quee.apk`. The artifact also holds `build.txt` with the build number.
5. Run the update test on the owner's phone (03 §7).
6. Owner confirms the release. Create a GitHub release in `ak2296/quee` with the tag `vYYYY.MM.DD` plus a letter or number suffix for several on the same day, mark it **latest**, and attach `Quee.apk` only. **The release notes must contain the line `build: <number from build.txt>`**: the app's update check reads it, and a release without it is ignored.
7. Add an entry to the change log below.

Notes from practice: the artifact download can fail on a dropped connection; retry. Tags used so far: `v2026.11.08`, `v2026.11.08b`, `v2026.11.12` … `v2026.11.12d`, `v2026.11.13` … `v2026.11.13i`.

## 4. Updating a running product

| Question | Answer |
|---|---|
| Do customers need to uninstall first? | No. Installing a new APK over the old one keeps all data. Uninstalling removes the data; the guide warns about it. |
| What makes an update possible? | The **same signing key** and the same package name. The CI verifies the key on every build. If the key ever changes, updates fail and data is lost. |
| What about version numbers? | Android refuses a lower build number. CI now sets it to the minutes since 1970, so it always rises (R-04). Releases before this change carry number 2. |
| What if a release is bad? | There is no rollback: Android does not install an older version over a newer one. Fix forward with a new release; keep earlier APKs as releases. |
| Will an old database upgrade? | `Database.open` upgrades step by step from any older version. This is **not yet tested** (G-3); do not rely on it for customers until it is. |
| Staged rollout? | No store. Use the owner's phone first, then one customer, then everyone (a manual canary). |
| Backups | Automatic encrypted backup; the guide tells customers to turn it on before they start. |
| Customer updates | The app looks for a newer release once a day (switch in Inställningar → Mer) and shows a card on Översikt with "Hämta och installera"; it downloads `Quee.apk` and opens Android's installer, which replaces the app and keeps the data. The first time Android asks to allow Quee to install apps. The download link on the page still works. The update feature is off in a Google Play build (`--dart-define=SELF_UPDATE=false`). |

## 5. Rollback and incident handling

1. Stop pointing customers at the new release: mark the previous release as **latest** in `ak2296/quee` (the download link follows "latest").
2. Tell affected customers to keep their data (do not uninstall) and to restore from backup only if data is missing.
3. Reproduce with the failing data, write a regression test, fix, run CI, run the update test, and publish a new release.

## 6. Configuration and secrets

| Secret | Where | Purpose |
|---|---|---|
| `ANDROID_KEYSTORE_ENC`, `ANDROID_KEYSTORE_PW` | GitHub repository secrets | Fixed signing key. Keep a safe copy outside GitHub (R-03). |
| Activation key pair | Owner keeps the secret key outside the repository | Signs activation codes; the app holds only the public key. |
| Gemini API key | The customer's own, in the app's secure storage | Optional online reading. |

No secrets are stored in the repository.

## 7. Change log

Releases from the download repository (all in November 2026). Descriptions are summarised from the commit history.

| Release | Date | Main changes |
|---|---|---|
| `v2026.11.13i` | 2026-11-13 | Enskild firma: yearly preliminary tax amount for the tax estimate |
| `v2026.11.13h` | 2026-11-13 | Resultat and estimated tax on Månad and År; equal-height key cards; "Nästa" due date in Att betala; Kommande betalningar removed |
| `v2026.11.13g` | 2026-11-13 | Half-width Säkerhetskopia and Att betala cards; red and brown amounts; scan button under the cards; "Importera fil" |
| `v2026.11.13f` | 2026-11-13 | Entry fields filled white like dropdowns |
| `v2026.11.13e` | 2026-11-13 | Backup card always shown; clearer field outlines |
| `v2026.11.13d` | 2026-11-13 | First-run tour; activation date and last backup on Översikt; "Fyll i" under the amount; thousands separator |
| `v2026.11.13c` | 2026-11-13 | One orange warning level; auto-formatted dates; PIN shake and vibration; floating nav fade; "dokument" wording |
| `v2026.11.13b` | 2026-11-13 | Expense counts on due date; one moms rate without duplicate amount |
| `v2026.11.13` | 2026-11-13 | Dark-mode warning fields; floating nav pill; "Faktura / kvitto"; Säkerhet cost type; stacked payslip dates |
| `v2026.11.12d` | 2026-11-12 | User guide 1.3 |
| `v2026.11.12c` | 2026-11-12 | "Ingen moms" makes moms fields inactive |
| `v2026.11.12b` | 2026-11-12 | Larm cost type; every-day month export; layout and tab changes; PIN grace 2 min; nav light |
| `v2026.11.12` | 2026-11-12 | Lönebesked, dark mode, fingerprint, swipe between tabs, grouped settings with search, new charts |
| `v2026.11.08b`, `v2026.11.08-quee`, `v2026.11.08` | 2026-11-08 | Earlier releases (before this period; not summarised here) |

Release notes in GitHub are shorter than this table; this table is the project's own record.

## 8. Pending release hygiene

- Build number is raised automatically (R-04, done in CI, awaiting the next release).
- Add the database upgrade test and run the update test for every release (G-3, R-01).
- Store a copy of the signing keystore safely (R-03).
- Add a visible version string in Om appen that matches the release tag.
