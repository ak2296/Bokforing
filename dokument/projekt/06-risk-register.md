# 06 – Risk register

Baseline: release `v2026.11.13i`. Scale: **Likelihood** and **Impact** are Low / Medium / High. **Rating** is the higher of the two unless noted.

| ID | Risk | Likelihood | Impact | Rating | Mitigation | Owner | Status |
|---|---|---|---|---|---|---|---|
| R-01 | **Data loss on update.** A customer updates from an old version and the database upgrade fails or loses data. | Medium | High | High | Add the database upgrade test (G-3 / F-26); run the update test before every release (03 §7); the automatic backup is the safety net and the guide tells customers to turn it on first. | Developer | Open |
| R-02 | **Wrong money shown or exported** (reading error, wrong date rule, rounding). | Medium | High | High | Rules in pure Dart with tests; user confirms every record; validation shows mismatches; add tests for the counting-date rule (G-1); the app labels moms and tax as estimates. | Developer | Open |
| R-03 | **Signing key lost or replaced.** Android refuses to install updates over existing installs; customers must uninstall and lose data. | Low | High | High | Keep the keystore secret and a copy of the keystore file in a safe place outside GitHub; never change it; CI verifies the certificate. | Owner | Open |
| R-04 | **Build number never raised** (CI now sets it from the clock; takes effect with the next release). `pubspec.yaml` stays at `0.2.0+2` and CI does not set a build number. Installs over older releases have worked so far with the same number, but Android refuses a lower number, and equal numbers make versions impossible to tell apart (and some phones or installers may refuse the update). | Medium | Medium | Medium | Let CI pass `--build-number` from the run number (or raise it in `pubspec.yaml` each release) and show the version in Om appen. Not yet done. | Developer | Open |
| R-05 | **Forgotten backup password or PIN.** The backup cannot be opened; without a backup the data is lost after a reinstall. | Medium | High | High | Clear warning when the PIN or backup is set; password written down; Översikt shows the backup state and last backup. | Owner | Mitigated |
| R-06 | **Phone lost or broken without a recent backup.** | Medium | High | High | Automatic backup to a folder that syncs to the cloud; "send copy" to a cloud service; backup card on Översikt. | Owner / customer | Mitigated |
| R-07 | **Only one test device.** Layout, permission or OCR differences on other phones and Android versions are unknown. | High | Medium | High | Test on at least one more phone and an older Android version before wider rollout (G-6). | Owner | Open |
| R-08 | **Tax or moms guidance misunderstood** as official advice. | Medium | High | High | Every moms and tax figure is labelled "beräknad" or "uppskattning"; the guide says the app does not replace a return; tax rate for AB (20,6 %) and moms rates are versioned and must be re-checked yearly. | Owner | Mitigated |
| R-09 | **Rule changes** (moms rates, SIE format, Skatteverket rules). The 6 % food rate end date is only from a secondary source. | Medium | Medium | Medium | Verify on skatteverket.se; keep rates in `VatRuleSet` with dates; review each January. | Owner | Open |
| R-10 | **Dependency or build breakage.** A package update or Flutter change breaks the CI build; the build uses patches on generated Android files. | Medium | Medium | Medium | Versions are pinned in `pubspec.yaml`; CI patches are explicit and fail loudly; keep previous releases. | Developer | Open |
| R-11 | **Single maintainer and no local Flutter.** Builds and tests only run in CI (about 11 minutes per run). | Medium | Medium | Medium | Keep documentation current (these files, HANDOFF); keep the CI green; consider a local setup. | Owner | Open |
| R-12 | **Distribution outside Google Play.** Phones warn about unknown apps; no store review or automatic updates. | High | Low | Medium | QR card and guide explain the prompt; releases published in one place; the user installs updates by hand. | Owner | Accepted |
| R-13 | **Online reading privacy.** If a customer turns on Gemini analysis, documents are sent to Google; terms differ by region. | Low | Medium | Medium | Off by default; own key; consent each time; clear text about what is sent. Check the terms before giving the app to others. | Owner | Mitigated |
| R-14 | **Accessibility shortfalls** (contrast, text size, screen reader) exclude some users. | Medium | Medium | Medium | Findings F-07, F-08; fix and re-test (G-7). | Developer | Open |
| R-15 | **Activation code misuse or expiry.** A copied code works on many phones; an ended customer keeps using the app. | Medium | Low | Low | Codes carry an end date and can be revoked in a later release; test code stops on a fixed date. Not a security boundary. | Owner | Accepted |
| R-16 | **Private data leaks into the repository** (real documents, bank file, payslips). | Low | High | Medium | Project rule: learn layouts only, never copy real data; tests use anonymised text; review before each commit; the repository is public. | Developer | Open |

## Notes

- The repository `ak2296/Bokforing` is public. R-16 therefore matters: anything committed is visible.
- The download repository `ak2296/quee` holds only the release APKs and the download page.
- Review this register at every release and whenever a risk changes; record the date and the changes below.

## Review log

| Date | Reviewer | Changes |
|---|---|---|
| 2026-11-13 | Developer (draft) | First version; for owner review |
