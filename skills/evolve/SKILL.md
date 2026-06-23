---
name: ss-evolve
description: Use periodically (or when the loop feels repetitive) to turn accumulated ledger signal into improvements — it detects recurring skips and failing gates, auto-applies low-risk doc/config fixes, and drafts new skills for your review.
---

# Evolve - learn from the ledger

Closes the loop: the ledger records what happened; `/ss-evolve` acts on it.

## Steps

1. Run `scripts/ss-evolve --json --new-only` to get unhandled patterns. If none, report
   "loop's running clean - nothing to evolve" and stop.
2. For each finding, read its evidence (and the relevant ledger notes / recent diffs if useful),
   then decide:
   - **Low-risk insight** (a convention or gotcha): author a tailored `CONTEXT.md` entry (richer
     than the built-in template), append it, and commit as `chore(evolve): <summary>`.
   - **A new skill is warranted** (a recurring multi-step fix worth codifying): write the full
     draft to `.superstack/proposals/<name>/SKILL.md` and validate its frontmatter (name `ss-*`,
     a `Use ...` description 40-500 chars, exactly one H1). Do NOT commit it - announce its path
     for the human to move into `skills/`.
3. After each change: record the finding id in `.superstack/evolve-state` and log
   `ledger evolve note na "<what happened>"`.
4. Announce what was auto-applied (with the `chore(evolve):` commits and how to `git revert`
   them) and what was proposed (with paths). If asked for a dry run, draft and show everything
   but apply nothing.

## Note

New skills are never auto-committed - they steer future agents, so they always go to
`.superstack/proposals/` for your review. Only documentation and config insights auto-apply.
`scripts/ss-evolve --apply` is the deterministic, no-LLM version (templated CONTEXT.md entries).

## Lineage

Original to SuperStack - the [[ss-audit]] ledger made it possible.
