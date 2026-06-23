# Contributing to SuperStack

SuperStack eats its own dog food: contributions go through the same loop the framework
preaches. Keep changes small, tested, and surgical.

## Quick start

```bash
git clone https://github.com/Mrshahidali420/superstack
cd superstack
bash scripts/lint-skills.sh   # must pass before you open a PR
bash tests/run.sh             # self-test the linter
```

## The skill contract

Every skill lives at `skills/<phase>/SKILL.md` and **must** start with frontmatter:

```markdown
---
name: ss-<something>          # must start with "ss-" (namespace, avoids collisions)
description: Use when ...      # trigger-focused, third person, says WHEN to fire
---
```

The directory name should match the command suffix (`skills/secure/` → `ss-secure`).
Agents live at `agents/ss-*.md` with the same `name` + `description` frontmatter.

`scripts/lint-skills.sh` enforces this and runs in CI on every push and PR — run it
locally first.

## Adding or changing a skill

1. **Frame** — open an issue describing the problem before writing. Push back on scope.
2. **Plan** — keep it to one skill (or one focused change) per PR.
3. **Build** — match the existing skill structure: a short intro, numbered steps, a
   **Gate**, and a **Lineage** line. Simplicity first — no speculative options.
4. **Review** — `bash scripts/lint-skills.sh` and `bash tests/run.sh` are green.
5. **Ship** — conventional commit (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`),
   then open a PR with a clear summary.

## Style

- One idea per skill. If a skill grows past ~60 lines, it is probably two skills.
- Keep the `/ss-*` namespace — it is what lets SuperStack coexist with other packs.
- Don't vendor upstream code. SuperStack re-implements ideas and credits them in
  `CREDITS.md`; PRs that paste in another project's files will be declined.
- Markdown, no build step, no runtime dependencies beyond `bash` + `jq` for the linter.

## What gets declined

- New runtime dependencies without a strong reason.
- Skills that duplicate an existing phase rather than improving it.
- Copied upstream files (see above).

By contributing you agree your work is released under the repository's MIT license.
