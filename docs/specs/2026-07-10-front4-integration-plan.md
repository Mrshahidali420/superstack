# Front 4 — integration — Implementation plan

Spec: `2026-07-10-front4-integration-design.md` (approved; see Build amendment in §2).
Four tasks, each gated by the committed test suite. bash + ps1 twins stay byte-parity
(see the parity gotchas: case-sensitive matching, LF endings, ordinal comparisons).

## Task 1: Doctrine template (single source)

**Files:** Create `templates/context-routing.md` — the marker-delimited block, LF endings.
**Verify:** `grep -c 'superstack:context-routing' templates/context-routing.md` → 2
(start + end marker); first line is exactly `<!-- superstack:context-routing -->`.

## Task 2: `/ss-init` installs the block (bash + ps1)

**Files:** Modify `scripts/ss-init`, `scripts/ss-init.ps1`, `tests/init.test.sh`.

Behavior (both twins, identical report bytes):
- New report row `routing:` after `ledger:`.
- Resolve template at `<script dir>/../templates/context-routing.md`;
  missing → `skipped (template missing)`.
- `--no-routing` / `-NoRouting` → `skipped (--no-routing)`.
- `--dry-run` → `[dry-run] would install the routing block into CLAUDE.md`.
- No `CLAUDE.md` → create it with exactly the block. Existing file without markers →
  ensure trailing newline, blank separator line, append block → `installed (CLAUDE.md)`.
- Markers present, block bytes == template → `already current`.
- Markers present, block differs → replace between markers (inclusive) → `updated (CLAUDE.md)`.
- `installed`/`updated` set the `wrote` flag (footer: "ready - ...").
- ps1 writes with **LF** endings (`[IO.File]::WriteAllText`, `"`n"` joins) — never
  `Add-Content`/`Set-Content` for CLAUDE.md (CRLF would break twin byte-parity).

Tests (RED first): fresh install row + markers present; idempotent re-run
(`already current`, cksum stable); update path (corrupted block → template bytes
restored, surrounding text preserved); `--no-routing` (no CLAUDE.md written);
dry-run writes nothing; **bash-written vs ps1-written CLAUDE.md byte-identical**;
existing dry-run report parity still passes with the new row.

## Task 3: Cockpit row 3 (bash + ps1)

**Files:** Modify `scripts/ss-context`, `scripts/ss-context.ps1`, `tests/context.test.sh`.

- Row: `printf '  %-18s %-13s %s\n' 'routing doctrine' ...` after `code exploration`.
- Detected: literal case-sensitive `<!-- superstack:context-routing -->` in `./CLAUDE.md`
  → hint `CLAUDE.md (superstack:context-routing)`.
- Not detected → hint `run /ss-init to install the routing block`.
- ps1: `Select-String -SimpleMatch -CaseSensitive` (parity gotcha).

Tests: detected/not-detected fixtures; mixed-case marker must NOT match; new fixtures
join the bash/ps1 parity loop; existing fixture rows unchanged.

## Task 4: Dogfood + docs

**Files:** Modify `CLAUDE.md` (via `bash scripts/ss-init` run at repo root — commit only
the CLAUDE.md change), `README.md`, `CHANGELOG.md`, `skills/init/SKILL.md`,
`skills/context/SKILL.md`.

- README: What's new gains the routing doctrine; dogfooding list says Fronts 1–4;
  roadmap drops Front 4 (leaves `/ss-panel`).
- CHANGELOG `[Unreleased]`: Front 4 entry.
- Skill docs: init documents the routing step + `--no-routing`; context documents row 3.
- Full suite: `bash tests/run.sh` → ALL TESTS PASS. Merge ff to main.
