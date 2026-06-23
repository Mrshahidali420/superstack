---
name: ss-qa
description: Use to validate that a change actually works in the running application, not just in tests. Exercises real user flows in a browser or CLI, finds and fixes bugs, and adds a regression test for every fix.
---

# QA

The fifth phase. Tests prove units work; QA proves the *thing* works.

## Steps

1. **Run the real feature** — launch the app, CLI, or endpoint the change affects.
2. **Drive the core flows** a user actually takes. Try the happy path, then the
   obvious ways it breaks (empty input, wrong order, slow network, back button).
3. **For each bug:** reproduce it → fix it → re-verify → **add a regression test** so
   it can't come back silently.
4. **Report with evidence** — what you exercised, what passed, what you fixed. Never
   claim a flow works without having run it. (Evidence over claims.)

## Gate

Core flows pass and every fix has a regression test. Then `/ss-secure`.

Record the outcome: `ledger qa gate pass` — or `ledger qa skip skip "<reason>"` if you deliberately skipped this phase.

## Note

SuperStack does not ship a browser. Use your agent's built-in browser tool, or run
gstack's `/browse` alongside for a hardened headless browser. For a CLI/API, exercise
it directly.

## Lineage

gstack `/qa` (test-find-fix-verify with regression tests).
