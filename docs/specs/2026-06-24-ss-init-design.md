# /ss-init — per-project bootstrap (v0.5.0+)

- **Date:** 2026-06-24
- **Status:** Approved (design)
- **Target version:** next release (currently `[Unreleased]`, alongside `/ss-replay`); skills count → 24.
- **Related:** `install.sh` (global plugin install — orthogonal), `scripts/ledger`, `scripts/ss-audit`, `scripts/ss-evolve`. Sibling slate item: `/ss-doctor` (#12, health-check — separate).

## 1. Context

After installing SuperStack (skills/agents into `~/.claude/` via `install.sh`), a user opens a project and… there's no guided first-run. `/ss-init` is the **per-project runtime bootstrap**: it makes the loop work immediately in *this* repo. It is orthogonal to `install.sh` (which is global, once-per-agent).

Live research (CLI `init`/scaffold best practices, 2026-06-24) gives the governing principle: **idempotent and non-destructive** — re-running produces the same result and never clobbers files the user edited unless `--force`; prefer **merge over overwrite**; offer `--dry-run` to print the plan before any write; sensible defaults, non-interactive (right for an agent-run command). Sources: k6 `x agent` bootstrap, AWS `cdk bootstrap`, npm `init`, "idempotent bash" (arslan.io).

## 2. Goals / Non-goals

**Goals**
- One command that makes a project loop-ready: a discoverable `config`, `.superstack/` gitignored, and a genesis ledger entry.
- **Idempotent & non-destructive by default**; `--dry-run` previews; `--force` resets the config only.
- Byte-identical bash + PowerShell twins; deterministic, parity-tested.

**Non-goals (deliberate)**
- Installing skills/agents — that's `install.sh` (global).
- Health/verification — that's `/ss-doctor` (#12).
- Interactive prompts — agent-run ⇒ non-interactive defaults.
- Pre-creating `ledger.jsonl` by hand — the `ledger` script lazily creates `.superstack/` + the file; `/ss-init` writes the genesis entry *through* `ledger`.

## 3. Repo facts relied on

- Runtime dir = `${SUPERSTACK_DIR:-.superstack}` across all scripts.
- `ledger <phase> <event> [status] [note]` validates `event ∈ {enter,gate,skip,note}` and `status ∈ {pass,fail,skip,na}`; **phase is unvalidated** (so `init` is a valid meta-phase). It `mkdir -p "$dir"` before the first append (`scripts/ledger`), so the dir + `ledger.jsonl` are created lazily.
- `config` keys (the only two any script reads, both default gracefully if absent): `mandatory_phases` (default `review,secure`, read by `ss-audit`) and `evolve_threshold` (default `3`, read by `ss-evolve`). Format `key=value`, one per line, `#` comments ignored by the `grep '^key='` readers.
- The SuperStack repo's own `.gitignore` ignores `.superstack/` (line 15) — but a *user's* project won't, so ensuring it is `/ss-init`'s job.

## 4. CLI surface

```
ss-init [--force] [--dry-run]
```
- `--force`: reset an existing `config` to defaults (overwrite). Affects **only** `config`.
- `--dry-run`: print the planned actions, write nothing, exit 0.
- No positional args. Unknown flag → stderr usage, exit 1.
- PowerShell: `-Force`, `-DryRun`. Output identical.

## 5. The three actions (each idempotent)

Let `dir = ${SUPERSTACK_DIR:-.superstack}`.

**A. `config` — write `dir/config` if absent (or on `--force`).**
- If `dir/config` does not exist → create it with:
  ```
  # SuperStack project config (key=value). Delete a line to use the built-in default.
  mandatory_phases=review,secure
  evolve_threshold=3
  ```
- If it exists and no `--force` → **skip** (don't clobber).
- If it exists and `--force` → overwrite with the same default content.

**B. `gitignore` — ensure `.superstack/` is ignored (git repos only).**
- Determine the repo root via `git rev-parse --show-toplevel`. If not inside a git repo → **skip** with a note (`not a git repo`).
- If `<root>/.gitignore` already contains a line exactly `.superstack/` or `.superstack` → **skip**.
- Otherwise append a line `.superstack/` (creating `.gitignore` if absent). Never duplicates.
- `--force` does **not** re-add it (idempotent regardless).

**C. `ledger` genesis — write one genesis entry if no ledger exists yet.**
- If `dir/ledger.jsonl` does not exist → call the sibling ledger (`ledger init note na "superstack loop initialized"`), which creates `dir/` + `ledger.jsonl`. bash `ss-init` calls the bash `ledger`; `ss-init.ps1` calls `ledger.ps1` (no cross-language dependency).
- If it exists → **skip** (don't add a second genesis). `--force` does not re-write it.

This dual-purposes as a smoke test that the ledger toolchain works, and gives `/ss-replay` a run-start marker. (Phase `init` is a meta-phase; it is an `event=note`, so it does not affect `ss-audit`'s gate check or inflate `ss-report`/`ss-replay` gate/skip counts; `ss-replay` will show one extra `init note` row.)

## 6. Output (ASCII, byte-identical twins)

Label column padded to width 10; value follows (no trailing padding → no rstrip needed). Header uses the literal `.superstack/` (matching the codebase's display convention, even when `SUPERSTACK_DIR` is overridden).

Fresh init:
```
ss-init: SuperStack project setup (.superstack/)
  config:    created (.superstack/config)
  gitignore: added .superstack/ to .gitignore
  ledger:    created (genesis entry)
ready - run /ss-frame to start the loop (see CLAUDE.md).
```
Idempotent re-run (all present):
```
ss-init: SuperStack project setup (.superstack/)
  config:    already present (use --force to reset)
  gitignore: already ignored
  ledger:    already present
already initialized.
```
`--dry-run` on a fresh project (writes nothing):
```
ss-init: SuperStack project setup (.superstack/)
  config:    [dry-run] would create .superstack/config
  gitignore: [dry-run] would add .superstack/ to .gitignore
  ledger:    [dry-run] would write a genesis entry
[dry-run] no changes written.
```
Per-state line strings (exact, both twins):
- config: `created (.superstack/config)` · `already present (use --force to reset)` · `reset (.superstack/config)` (on `--force`) · `[dry-run] would create .superstack/config` · `[dry-run] would reset .superstack/config`
- gitignore: `added .superstack/ to .gitignore` · `already ignored` · `skipped (not a git repo)` · `[dry-run] would add .superstack/ to .gitignore`
- ledger: `created (genesis entry)` · `already present` · `[dry-run] would write a genesis entry`
- footer: `ready - run /ss-frame to start the loop (see CLAUDE.md).` (any write happened) · `already initialized.` (all present, no writes) · `[dry-run] no changes written.` (dry-run)

## 7. Parity mechanics

bash + `.ps1` twins, ASCII only, identical stdout. Because a non-dry run mutates state (so a second invocation sees a different state), the **parity test uses `--dry-run`** on a fresh fixture so both twins print the identical plan. The genesis entry's JSON is written via each twin's own-language `ledger` (timestamps differ, so the ledger file content is not byte-compared across platforms — only `ss-init`'s stdout is).

## 8. Test plan

New `tests/init.test.sh`, wired into `tests/run.sh` (`[N/8]`→`[N/9]`). Each test runs in a fresh `git init` tmp dir with `SUPERSTACK_DIR` set under it.

1. **Fresh init** — creates `config`, adds `.superstack/` to `.gitignore`, writes a genesis ledger entry; stdout shows `created`/`added`/`created (genesis entry)` and footer `ready - ...`.
2. **Config content** — `config` contains the comment line, `mandatory_phases=review,secure`, and `evolve_threshold=3`.
3. **Genesis entry** — `ledger.jsonl` has exactly one line, an `init`/`note` entry with the genesis note.
4. **Idempotent re-run** — a second `ss-init` writes nothing new: `config` byte-unchanged, `.gitignore` contains `.superstack/` exactly once, `ledger.jsonl` still one line; stdout shows `already present`/`already ignored`/`already present`, footer `already initialized.`
5. **`--force`** — after editing `config`, `ss-init --force` resets it to defaults; `.gitignore` still has one `.superstack/` line; `ledger.jsonl` still one line (no second genesis).
6. **`--dry-run`** — on a fresh project prints the `[dry-run] would ...` plan and footer; creates **no** `config`, makes **no** `.gitignore` change, writes **no** ledger.
7. **Not a git repo** — in a non-git tmp dir, the gitignore step prints `skipped (not a git repo)`; config + genesis still happen.
8. **Parity** — bash vs `pwsh` byte-identical for `--dry-run` on a fresh fixture (skipped when `pwsh` absent, same guard as the suite).

## 9. Docs / version impact

- `skills/init/SKILL.md` — the `/ss-init` skill (run once per new project, before the loop). Lineage notes it's the per-project counterpart to `install.sh`.
- `README.md` — add `/ss-init` to the commands surface; skills count → **24**; ideally a one-line "Quickstart: `/plugin install` → `/ss-init` → `/ss-frame`".
- `CHANGELOG.md` — `[Unreleased]` `### Added` entry.

## 10. Risks

- **gitignore root vs cwd** — `.superstack/` is created cwd-relative (like all scripts), but the gitignore line `.superstack/` is unanchored so it matches anywhere; written at the git root so it covers the dir regardless of where `ss-init` ran.
- **`SUPERSTACK_DIR` override** — display/gitignore use the literal `.superstack/`; a user who overrides `SUPERSTACK_DIR` to a different path manages their own gitignore (documented, not auto-handled — YAGNI).
- **`--force` scope** — deliberately resets only `config` (the user-editable file); never re-adds the gitignore line or a second genesis entry. Tested.
