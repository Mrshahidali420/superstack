---
name: ss-ship
description: Use when a change is reviewed, tested, and ready to land. Syncs the base branch, runs the full suite, audits coverage, makes a conventional commit, opens a PR, and optionally deploys and verifies production health.
---

# Ship

The seventh phase. Land the work cleanly.

## Steps

1. **Audit the process first.** Run `/ss-audit` (or `scripts/ss-audit`). If INCOMPLETE, stop and
   close the gap (run the missing phase or record an explicit skip) before continuing. When
   COMPLETE, capture the attestation with `scripts/ss-audit --attest` and include it in the PR body.
2. **Sync the base branch** and resolve any conflicts.
3. **Run the full test suite.** If the project has no tests, bootstrap a framework and
   add the missing coverage before shipping. Audit coverage on the diff.
4. **Update `CHANGELOG.md`.** Move the `[Unreleased]` entries under a new version heading
   with today's date (create the entry, in Keep a Changelog format, if it's missing). When
   cutting a release, bump the version in any manifest (e.g. `plugin.json`) to match.
5. **Conventional commit** — `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`,
   `perf:`, `ci:` — with a clear subject and a body explaining the why.
6. **Open a PR** with a summary of the change and a test plan. Analyze the full commit
   history, not just the last commit, when writing the description.
7. **Optional deploy** — merge, wait for CI and the deploy, then verify production health
   (smoke the key endpoints, watch for console/log errors).
8. **Finish the branch** — present the merge / PR / keep / discard decision and clean up.

> Optional: run `/ss-report` for a shareable summary of how this change was built (phases, timing, size) — paste it into the PR or share it.

## Gate

CI is green and the PR is open (or the change is merged and verified in production).

Record the outcome: `ledger ship gate pass` — or `ledger ship skip skip "<reason>"` if you deliberately skipped this phase.

## Lineage

gstack `/ship` + `/land-and-deploy` + Superpowers `finishing-a-development-branch` + GSD `ship`.
