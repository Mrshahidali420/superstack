# /ss-context — standing-context cockpit (v0.7.0+, Front 1 of the context all-rounder)

- **Date:** 2026-06-25
- **Status:** Approved (design)
- **Target version:** next release (`[Unreleased]`, the pending v0.7.0 cut); skills count → 29.
- **Program context:** Front 1 of a 4-front "context all-rounder" (1: standing context [this]; 2: native `ss-ctx` runtime-output sandbox; 3: native `ss-munch` code retrieval; 4: loop integration). Fronts 2–3 are separate specs/builds (new TS + MCP). This front is a read-only bash+PowerShell twin + a SessionStart-hook advisory.
- **Related:** `/ss-doctor` (health check — checks no sizes; no overlap), `/ss-init` (writes `.superstack/`), the SessionStart hook (`hooks/session-start`). Composes with external **context-mode** / **jcodemunch** MCP servers (detected, not bundled).

## 1. Context

SuperStack preaches context engineering (CLAUDE.md §"Context Engineering": context rot, offload to subagents, durable `STATE.md`/`CONTEXT.md`, right-size tasks) but has no way to *see* the budget. Live research (2026-06-25) gives the model: **"budget by fill percentage, not raw tokens, and compact proactively past ~60%"**; **`CLAUDE.md` is never evicted** so its size is a permanent per-session cost; offload verbose work to subagents. The mature MCP tools attack *runtime* context — [context-mode](https://github.com/mksglu/context-mode) sandboxes tool output, [jcodemunch](https://github.com/jgravelle/jcodemunch-mcp) does symbol-level retrieval — but **nothing watches the *standing* on-disk footprint** (the always-loaded files). That's this front.

A bash/ps1 script cannot read the live context window — only files on disk. So `/ss-context` measures the **standing footprint** (the project's always-loaded files) against a budget, flags bloat, detects the rest of the context stack, and — the headline — runs **automatically** in the SessionStart hook to nudge you *only when you're over budget*.

## 2. Goals / Non-goals

**Goals**
- **Automatic** standing-context advisory at session start (via the existing SessionStart hook) — silent when fine, one line when over the warn threshold. No command needed.
- On-demand `/ss-context` report: footprint table, budget %, context-stack detection, bloat flags + recommendations. CI-gateable.
- Derive everything from disk; no new recording; compose with (detect, don't bundle) context-mode/jcodemunch.
- Byte-identical bash + PowerShell twins for the command; the hook stays bash-only (run cross-platform via `run-hook.cmd`, as the other hooks are).

**Non-goals (deliberate)**
- Measuring the live context window / token count (impossible from disk — the estimate is `bytes/4`, labeled a heuristic).
- Runtime tool-output sandboxing or code retrieval — those are Fronts 2–3 (and the external MCP tools); this front only *detects* them.
- Auto-trimming/deleting/archiving (read-only; recommends only — respects the delete prohibition).
- A config key for the budget (YAGNI for v1 — `--budget` flag + default; a `context_budget` config key can come in Front 4).

## 3. Repo facts relied on

- SessionStart hook `hooks/session-start` (bash): reads `skills/superstack/SKILL.md`, wraps it in `<EXTREMELY_IMPORTANT>`, emits `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"…"}}` (Claude Code) or `{"additional_context":"…"}` (else), via an `escape_json()` helper; runs under `set -euo pipefail`. Wired in `hooks/hooks.json` under `SessionStart` matcher `startup|clear|compact`, launched by `hooks/run-hook.cmd session-start`. Hooks are bash-only (no `.ps1` twins).
- House conventions: bash + `.ps1` command twins; `${SUPERSTACK_DIR:-.superstack}`; ASCII-only; 54-dash separators; exit `0`/`1`/`2`; `chk`/`newrepo` tests; `tests/run.sh` now `[1/13]..[13/13]`; the self-test already covers "session-start emits valid JSON" — extend it. `ss-doctor` is the closest sibling (read-only multi-check report with `[OK]`/`[WARN]`/`[FAIL]` rows + verdict footer + exit 0/1/2).
- MCP config is discoverable on disk: project `.mcp.json`, user `~/.claude.json`, `.claude/settings.json` — a script can grep them for server names.

## 4. CLI surface + automatic advisory

```
ss-context [--budget N] [--check]
```
- `--budget N`: token budget for the standing footprint (default **8000**).
- `--check`: **hook/quiet mode** — print nothing when under the warn threshold, one advisory line when WARN/OVER; **always exit 0** (never break the hook). Without `--check`, print the full report.
- Unknown flag / bad `--budget` (non-positive-int) → stderr usage, **exit 1**.
- **No `jq` dependency** (pure file sizes + frontmatter text).
- PowerShell: `-Budget`, `-Check`. Output identical.
- **Exit (full report):** `0` when OK/WARN, **`1` when OVER** (CI gate), `2` usage. **`--check` always exits 0.**

**Automatic integration:** `hooks/session-start` runs `ss-context --check` (cwd = project root) and, if it printed a line, appends it to the bootstrap `additionalContext` (escaped). Guarded so a failure/absence is silent and never breaks session start. → every session warns you iff your standing context is over budget; otherwise zero noise.

## 5. Computation

All sizes from disk in the **current working directory** (the project). Est. tokens = `floor(bytes/4)` (a rough ~4-chars/token heuristic; labeled "est" in output).

**Standing footprint** (the budgeted set — always-loaded, user-controllable files), each counted only if present:
- `CLAUDE.md`, `AGENTS.md`, `STATE.md`, `CONTEXT.md` (repo root).
- **skill descriptions**: if a `skills/` dir exists, the summed byte length of the `description:` frontmatter value across `skills/*/SKILL.md` (+ a count). (Always-loaded part; bodies are on-demand. Present when dogfooding in the SuperStack repo or a project with local skills; absent → omitted.)

`total_tokens` = sum of the above est. tokens. `pct = round(100*total_tokens/budget)`. Verdict: **OK** (`pct < 60`), **WARN** (`60 <= pct <= 100`), **OVER** (`pct > 100`).

**Context-stack detection** (the other two fronts; each → `detected` / `not detected` + a hint):
- **runtime sandbox**: native `scripts/ss-ctx` exists (Front 2) OR `context-mode` appears in `.mcp.json` / `~/.claude.json`.
- **code exploration**: native `scripts/ss-munch` exists (Front 3) OR `jcodemunch` appears in those configs.
(Forward-compatible: detects the native tools once Fronts 2–3 land, and the external MCP servers meanwhile.)

**Flags** (bloat, each with a one-line recommendation; only emitted when tripped):
- `CLAUDE.md` > 16 KB → "trim to stable instructions (it is never evicted)".
- `STATE.md` or `CONTEXT.md` > 8 KB → "compact via /ss-learn".
- `${SUPERSTACK_DIR}/ledger.jsonl` > 1000 lines → "archive old entries".
- `${SUPERSTACK_DIR}/replays/` + `proposals/` combined > 5 MB → "archive".

Flags are **advisory**: they appear in the full report regardless of the budget verdict and do **not** change the verdict or exit code — only the budget `pct` drives the verdict (`OK`/`WARN`/`OVER`) and the exit code (`1` only on `OVER`). The `--check` advisory fires on the **budget threshold** (`pct >= 60`), not on flags; when it fires, it cites the first tripped flag's recommendation (or a generic "review /ss-context") to suggest what to trim.

## 6. Output (ASCII, byte-identical twins)

Full report:
```
ss-context: standing context budget
------------------------------------------------------
artifact            bytes   ~tokens
CLAUDE.md           7560    1890
STATE.md            612     153
CONTEXT.md          980     245
skill descs (28)    7100    1775
------------------------------------------------------
session-start: ~4063 tokens / 8000 budget (51%)   OK
------------------------------------------------------
context stack:
  runtime sandbox    detected      context-mode (mcp)
  code exploration   not detected  front 3 (ss-munch) or install jcodemunch
------------------------------------------------------
flags:
  ! ledger.jsonl 1240 lines - archive old entries
verdict: OK   (warn >=60%, over >100%)
```
- **Header** `ss-context: standing context budget`, 54-dash sep.
- **Footprint table**: header row `artifact            bytes   ~tokens` (fixed widths `%-18s%-8s%s`); one row per present artifact; the skill-descs row is `skill descs (<n>)`. Sep.
- **Budget line**: `session-start: ~<T> tokens / <B> budget (<pct>%)   <OK|WARN|OVER>` (3 spaces before verdict). Sep.
- **context stack**: label `context stack:` then two `  %-18s %-13s %s` rows (capability, detected|not detected, hint). Sep.
- **flags**: label `flags:` then `  ! <artifact> <metric> - <recommendation>` per tripped flag, or `  (none)` if clean. 
- **verdict** footer: `verdict: <OK|WARN|OVER>   (warn >=60%, over >100%)`.
- **`--check` output**: nothing if OK; else one line: `[ss-context] standing context ~<T> tok = <pct>% of <B> budget - <first tripped flag's recommendation, or "review /ss-context"> (run /ss-context)`.

## 7. Hook integration (the automatic part)

Extend `hooks/session-start` (bash): after building `$context`, before emitting JSON, run
```
adv="$(bash "${PLUGIN_ROOT}/scripts/ss-context" --check 2>/dev/null || true)"
[ -n "$adv" ] && context="${context}\n\n$(escape_json "$adv")"
```
So the advisory (already a single ASCII line) is appended inside the `additionalContext` only when non-empty. `|| true` + `2>/dev/null` ensure the hook never fails or emits noise if `ss-context` is missing or errors. When OK, `$adv` is empty → byte-identical to today's hook output (no regression). `ss-context --check` measures the cwd, which Claude Code sets to the project root for hooks.

## 8. Parity mechanics

bash uses `wc -c`/`wc -l`/`stat` + `awk` (frontmatter `description:` extraction) + `grep` (MCP-config detection); ps1 uses `(Get-Item).Length` / `Get-Content` + string parsing. The `bytes/4` floor, the `pct` rounding (`round` — define identically: `floor(100*t/b + 0.5)` in both, integer-only to avoid rounding-mode drift), the verdict thresholds, the fixed column widths, the detection signals, and the flag thresholds are defined identically. ps1 sets nothing locale-sensitive; any sort uses `[System.StringComparer]::Ordinal`; `$PSNativeCommandUseErrorActionPreference=$false` if it shells to git (it does not here). The skill-descs sum iterates `skills/*/SKILL.md` in ordinal path order (matches bash `LC_ALL=C` glob) — though order doesn't affect the sum.

## 9. Test plan

New `tests/context.test.sh`, wired into `tests/run.sh` (`[13/13]`→`[14/14]`). Fixtures are `mktemp` project dirs with known-size `CLAUDE.md`/`STATE.md`/etc. so tokens are deterministic.

1. **Footprint + budget OK** — a small fixture → table lists present artifacts with `bytes/4` tokens; budget line shows `OK` and the right `pct`; exit 0.
2. **WARN / OVER** — sized fixtures crossing 60% and 100% of a small `--budget` → `WARN` / `OVER`; OVER exits **1**.
3. **`--check` quiet** — OK fixture → `--check` prints nothing, exit 0; OVER fixture → one `[ss-context] …` line, exit 0.
4. **Context-stack detection** — a fixture `.mcp.json` mentioning `context-mode` → `runtime sandbox detected`; a `scripts/ss-munch` stub → `code exploration detected`; neither → `not detected` + hint.
5. **Flags** — an oversized `CLAUDE.md` / a >1000-line `ledger.jsonl` → the matching flag line + recommendation; clean fixture → `(none)`.
6. **Usage** — bad `--budget 0`/`x` / unknown flag → exit 1.
7. **Hook advisory** — extend the hook self-test: with an OVER fixture as cwd, `hooks/session-start` output **contains** the advisory (and is valid JSON); with an OK fixture, the output is unchanged/valid and contains **no** advisory.
8. **Parity** — bash vs `pwsh` byte-identical on the full-report fixture and a `--check` OVER fixture (skipped when `pwsh` absent).

## 10. Docs / version impact

- `skills/context/SKILL.md` — the `/ss-context` skill + the **autopilot playbook**: read the advisory; on WARN/OVER apply the levers (`/compact` at ~50%/phase boundaries, `/clear` on task switch, offload to subagents, trim `CLAUDE.md`/`STATE.md`, archive the ledger); the **routing doctrine** (prefer the runtime sandbox + code-exploration tools when present, fall back to Read/Grep); a **right-size** note for Plan. Lineage: Front 1 of the context all-rounder; complements [[ss-doctor]] (health, not size) and the external context-mode/jcodemunch.
- `README.md` — add `/ss-context` to the supporting-skills inline list; skills count → **29**; (a short "context stack" note is a Front-4 doc task, not here).
- `CHANGELOG.md` — `[Unreleased]` `### Added` entry (joins `/ss-stats`, `/ss-trace`).

## 11. Risks

- **Hook regression** — the SessionStart hook is loaded every session; the advisory must be silent when OK and never break the hook. Mitigated by `|| true`/`2>/dev/null`, the empty-advisory = byte-identical-to-today path, and the hook self-test covering both OK (no change) and OVER (advisory present) cases.
- **Token heuristic** — `bytes/4` is approximate; the value is directional (is my standing context bloating?), labeled "est" in output. Acceptable per the research ("budget by %, directional").
- **What "standing" means per project** — in a user project the budget is driven by their `CLAUDE.md`/`STATE.md`/`CONTEXT.md` (skill descs only when local `skills/` exists, e.g. the SuperStack repo). Documented; the measured set is exactly the user-controllable always-loaded files.
- **Detection heuristics** — MCP-config grep can false-negative if a project uses a non-standard config path; the native-script check is exact. Detection is advisory (display-only); the footprint/budget are unaffected.
- **Parity (rounding)** — `pct` uses integer `floor(100*t/b + 0.5)` in both twins to avoid banker's-rounding drift; `bytes/4` is floor in both.
