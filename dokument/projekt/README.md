# Quee – project documentation

Project documents for **Quee**, a local-first Swedish bookkeeping assistant for small businesses (Flutter, Android first). The app UI is Swedish; these documents are in English and quote UI text as it appears in the app.

## Document set

| No. | Document | Purpose | Status |
|---|---|---|---|
| 01 | [Requirements and user stories](01-requirements.md) | What the product must do, with acceptance criteria and traceability to tests | Baseline for release 2026.11.13 |
| 02 | [Design document](02-design.md) | Architecture, modules, data model, key flows, design decisions, security | Baseline |
| 03 | [Test plan](03-test-plan.md) | Test strategy, levels, environments, entry and exit criteria, manual checklist | Baseline |
| 04 | [Test report](04-test-report.md) | What exists and what was verified for the current release, with gaps | Release 2026.11.13i |
| 05 | [Review and inspection record](05-review-record.md) | Findings from code, UX, security and documentation reviews, with status | Open items listed |
| 06 | [Risk register](06-risk-register.md) | Project and product risks, owner, mitigation | Baseline |
| 07 | [Release and deployment notes](07-release-and-deployment.md) | Build pipeline, signing, how a release is made, update rules, change log | Release 2026.11.13i |

Related files outside this folder:

- `PRODUCT.md` – product purpose, users, positioning and principles.
- `HANDOFF.md` – the full context handed to a developer, including the owner's decisions.
- `FUTURE_FUNCTIONS.md` – ideas not built yet, including features that need a company.
- `dokument/anvandarguide/` – the end-user guide (A5 PDF and A6 booklet).
- `graphify-out/` – a generated knowledge graph of the code (local only, not part of the baseline).

## Document control

- **Owner:** the product owner (the person who runs the business that uses the app).
- **Written from:** the repository at commit `8204b71` (2026-11-13) and release `v2026.11.13i`.
- **How these were made:** drafted from the code, tests, CI workflow, commit history and the decisions recorded in the project. Where something could not be verified it is marked **Not verified** or **Assumption**. Nothing here was invented to fill a gap.
- **Updating:** change a document in the same commit as the change it describes. Re-date the "Written from" line when a baseline is re-issued.
- **Reading order:** 01 (what) → 02 (how) → 03 and 04 (proof) → 05 and 06 (what is still wrong or risky) → 07 (how it ships).

## Conventions

- Requirement IDs: `FR-` functional, `NFR-` non-functional, `US-` user story.
- Review findings: `F-` followed by a number. Risks: `R-` followed by a number.
- Severity: **High** (data loss, wrong money, security), **Medium** (wrong or confusing behaviour with a workaround), **Low** (polish).
- "Money" is always integer öre inside the code; amounts in documents are written in kronor.
