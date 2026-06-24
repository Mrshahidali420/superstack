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
   - **A new skill is warranted** (a recurring multi-step fix worth codifying): run
     `scripts/ss-evolve --explore` to deterministically scaffold a valid stub at
     `.superstack/proposals/<name>/SKILL.md` (frontmatter + ledger evidence + a `<!-- TODO -->`
     body). Then author the `## Proposed behavior` body in that stub — a real, tailored skill
     per writing conventions (name `ss-*`, a `Use ...` description 40-500 chars, exactly one H1).
     Do NOT commit it - announce its path for the human to move into `skills/`.
3. After each change: record the finding id in `.superstack/evolve-state` and log
   `ledger evolve note na "<what happened>"`.
4. Announce what was auto-applied (with the `chore(evolve):` commits and how to `git revert`
   them) and what was proposed (with paths). If asked for a dry run, draft and show everything
   but apply nothing.
5. Scope to a recent window when the ledger is long: `scripts/ss-evolve --since 7d` (also `24h`
   or an absolute `YYYY-MM-DD`) filters detection to that slice. Composes with `--json`,
   `--new-only`, `--apply`, and `--explore`.

## Note

New skills are never auto-committed - they steer future agents, so they always go to
`.superstack/proposals/` for your review. Only documentation and config insights auto-apply.
Two deterministic, no-LLM script paths back this: `scripts/ss-evolve --apply` writes templated
`CONTEXT.md` entries (Tier 1, auto-commit), and `scripts/ss-evolve --explore` scaffolds proposal
stubs into `.superstack/proposals/` (Tier 2, never committed). They dedup independently
(`evolve-state` vs `explore-state`), so the same finding can be both documented and proposed.

## Lineage

Original to SuperStack - the [[ss-audit]] ledger made it possible.
