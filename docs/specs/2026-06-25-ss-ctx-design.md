# ss-ctx (Front 2a: transparent tool-output shrinker) — Design

> Front 2 of SuperStack's "context all-rounder" rebuilds, natively and inspiration-only, the
> context-saving capability of context-mode + jcodemunch. Front 2 splits into **2a** (this doc — the
> always-on output shrinker, zero-runtime) and **2b** (a later cycle — an MCP server adding sandboxed
> execution + FTS5 search over the same store).

## Problem

In agentic coding sessions, **tool results are ~49–73% of context tokens** (audited Claude Code
sessions; anthropics/claude-code#29971). The dominant source is verbose **Bash** output — test runs,
builds, `git log`, dependency installs, log dumps — most of which the agent reads once and never needs
verbatim again, yet it sits in the window forever (until compaction) crowding out reasoning room.

context-mode (mksglu) attacks this with **block-and-redirect**: a PreToolUse hook *denies* curl/wget/
big-Bash and *nudges* the agent to call its MCP `ctx_*` tools instead. That works only if the agent
complies, and it requires a long-running Node MCP server + native SQLite.

## Approach — transparent shrink, zero runtime

As of **Claude Code v2.1.121+**, a `PostToolUse` hook can **transparently replace** a built-in tool's
output via `hookSpecificOutput.updatedToolOutput` (docs: code.claude.com/docs/en/hooks; anthropics/
claude-code#32105, #41087). This post-dates context-mode's architecture and is strictly better for our
purpose: no agent compliance, no MCP server, no SQLite — a single bash hook intercepts an oversized
Bash result, saves the full text to disk, and substitutes a compact summary the agent still sees inline.

This fits SuperStack exactly: bash hooks (cross-platform via `run-hook.cmd`) + files + the `.superstack/`
tree, the same idiom as the SessionStart and PreToolUse hooks. It also lights up the **Front-1 cockpit**:
`/ss-context` already probes for `scripts/ss-ctx` and reports `runtime sandbox: detected (native)` once
it exists.

### Verified primitive (authoritative, from the hooks reference)

- **PostToolUse input** (stdin JSON): `{ session_id, cwd, hook_event_name:"PostToolUse", tool_name,
  tool_input, tool_response, tool_use_id, duration_ms, ... }`. The tool's result is in **`tool_response`**;
  its shape **depends on the tool**. For **Bash** it is a structured object
  `{ stdout, stderr, interrupted, isImage }`.
- **Replacement** (stdout JSON): `{ "hookSpecificOutput": { "hookEventName": "PostToolUse",
  "updatedToolOutput": <value matching the tool's output shape> } }`. The docs are explicit: with
  `decision:"block"` "Claude still sees the original output; **to replace it, use `updatedToolOutput`**."
- **Schema-match caveat:** "For built-in tools, a value that does not match the tool's output schema is
  ignored and the original output is used." → our Bash replacement MUST be a full
  `{ stdout, stderr, interrupted, isImage }` object (we replace `stdout`, pass the other three through
  unchanged).
- **Already executed:** the tool ran before the hook fires — this is display-only substitution; no side
  effects are prevented. Safe for a read-reducer.

## Scope (v1)

**Target the `Bash` tool only.** Rationale: (1) it is the dominant source of output bloat; (2) it is the
one built-in whose output schema the docs document explicitly (`{stdout,stderr,interrupted,isImage}`),
so we can satisfy the schema-match requirement with confidence; (3) KISS/YAGNI. Grep, WebFetch, and
large Read are **deferred** — their `tool_response` shapes must be verified empirically first, and Read
must never be shrunk (the agent needs verbatim content to Edit accurately). This is a deliberate
reduction from the brainstorm's "Bash/WebFetch/Grep"; the hook is written so adding a tool later is a
localized change.

## Behavior

The hook (`hooks/posttool-shrink`, bash, registered as `PostToolUse` matcher `Bash`):

1. Read stdin JSON. Require `jq`; **if `jq` is absent, emit nothing and exit 0** (no-op → original
   output passes through; never break the session).
2. **No-op (emit nothing, exit 0) unless ALL hold:**
   - `SS_CTX_DISABLE` is unset/empty (global off-switch).
   - `tool_name == "Bash"`.
   - `tool_response.stderr` is empty AND `tool_response.interrupted != true` (never shrink errors or
     interrupted runs — the agent needs that detail; docs warn explicitly).
   - `tool_response.stdout` byte length `> threshold` (default **8000** bytes ≈ 2000 tokens; override
     via `SS_CTX_THRESHOLD`).
3. **Offload:** write the full `stdout` verbatim to `${SUPERSTACK_DIR:-.superstack}/ctx/<id>.txt`, where
   `<id>` is the sanitized `tool_use_id` (unique per call; no timestamp/random needed). `mkdir -p` the
   dir.
4. **Summarize:** build `stdout'` = first **30** lines + a divider + last **15** lines of the original
   (head/tail counts override via `SS_CTX_HEAD`/`SS_CTX_TAIL`), then append one marker line:
   `[ss-ctx] elided <N> lines / <B> bytes - full output: <relpath> - retrieve: /ss-ctx show <id>`
   (counts are the elided middle, not the kept head+tail).
5. **Emit** (via `jq`, so all escaping is correct):
   `{ "hookSpecificOutput": { "hookEventName": "PostToolUse",
      "updatedToolOutput": { "stdout": <stdout'>, "stderr": <orig>, "interrupted": <orig>,
      "isImage": <orig> } } }`. Exit 0.

Nothing is ever lost: the full output is on disk, the marker tells the agent where and how to get it,
and the next layer (2b) will index the same store for search.

### Configuration (env)

| Var | Default | Effect |
| --- | --- | --- |
| `SS_CTX_DISABLE` | unset | Any non-empty value → hook is a global no-op. |
| `SS_CTX_THRESHOLD` | `8000` | Min `stdout` bytes to trigger shrinking. |
| `SS_CTX_HEAD` / `SS_CTX_TAIL` | `30` / `15` | Lines kept from the head / tail. |
| `SUPERSTACK_DIR` | `.superstack` | Store root (`<dir>/ctx/`). |

## Retrieval — `/ss-ctx`

`scripts/ss-ctx` (+ `scripts/ss-ctx.ps1` twin) — read-only access to the offload store:

- `ss-ctx list` — recent offloaded outputs: `<id>  <bytes>  <mtime>` (newest first).
- `ss-ctx show <id>` — print the full saved output (the thing the agent retrieves after seeing a marker).
- `ss-ctx search <term>` — grep across the store; print `<id>: <matching line>` hits.
- `ss-ctx prune [--keep N]` — delete all but the N newest (default keep 50); the only mutating subcommand,
  and it touches only `<dir>/ctx/`.
- no/unknown args → usage on stderr, exit 2.

The script's mere existence flips Front-1's `runtime sandbox: detected (native)` row. `scripts/ss-ctx`
(bash) + `scripts/ss-ctx.ps1` (PowerShell) must be **byte-identical** in output (the project's twin law).

## Components / files

- `hooks/posttool-shrink` — the bash PostToolUse hook (no `.ps1` twin; SuperStack hooks are bash-only).
- `hooks/hooks.json` — add a `PostToolUse` entry, matcher `Bash`, → `run-hook.cmd posttool-shrink`.
- `scripts/ss-ctx` + `scripts/ss-ctx.ps1` — retrieval/management twins.
- `skills/ctx/SKILL.md` — the `/ss-ctx` skill (when/why, the marker, retrieval, links `[[ss-context]]`).
- `tests/ctx.test.sh` — hook unit tests (sample input JSON → assert output JSON) + retrieval parity.
- `tests/run.sh` — wire `[15/15]`.
- `README.md`, `CHANGELOG.md` — surface it (30 skills).

## Safety / privacy

- Display-only: the command already ran; the hook changes only what the agent re-reads. No new side
  effects.
- Errors preserved: `stderr` and interrupted/failed runs are never shrunk.
- Reversible + lossless: full output on disk; off-switch (`SS_CTX_DISABLE`); generous default threshold
  so only genuinely large clean output is touched.
- Fail-safe: missing `jq`, malformed input, or any error → emit nothing → original output stands. The
  hook can never break a session.
- The store may contain command output (potentially secrets in logs). It lives under `.superstack/ctx/`
  (same trust boundary as the ledger); `ss-ctx prune` clears it. Document this.

## Testing

- **Hook unit tests** (the part we control): feed `hooks/posttool-shrink` a crafted PostToolUse input
  JSON on stdin; assert: under-threshold → empty output (no-op); over-threshold clean stdout → valid
  JSON with `hookSpecificOutput.updatedToolOutput.stdout` = head+tail+marker, other three fields
  preserved, and `<dir>/ctx/<id>.txt` written with the full original; stderr-present / interrupted /
  non-Bash / `SS_CTX_DISABLE` → no-op; absent `jq` → no-op. Validate emitted JSON with `jq -e`.
- **Retrieval parity:** `ss-ctx list/show/search` bash vs `.ps1` byte-identical on a seeded store
  (HOME/locale pinned; mixed-case + ordinal fixtures per the parity playbook).
- **Integration smoke test** (manual, build-time): wire the hook, run a real `Bash` command that emits
  >8000 bytes, confirm the model receives the summary + marker and that `ss-ctx show <id>` returns the
  full text. This is the one assertion unit tests can't make (that Claude Code sends the documented
  input and honors `updatedToolOutput`); the schema is otherwise confirmed from the authoritative docs.

## Out of scope (Front 2b and beyond)

- The MCP server: `ctx_execute` / `ctx_batch_execute` (sandboxed run, capture stdout) + SQLite **FTS5**
  `ctx_search` over the `.superstack/ctx/` store this front fills.
- Additional tools (Grep, WebFetch, large Read) once their output schemas are verified.
- Semantic/LLM summarization (this front is deterministic head/tail truncation only).
- PreToolUse command rewriting (`updatedInput`) — possible later, not needed for the core value.

## Decided defaults (open to review)

- Bash-only v1 (scope reduction, justified above).
- 8000-byte threshold; head 30 / tail 15; all env-overridable.
- `jq` required for the hook (graceful no-op fallback) — unlike `/ss-context`, which is jq-free, because
  robustly parsing/​re-emitting arbitrary stdout demands a real JSON parser.
- On by default (the whole point is automatic), but only touches large, clean, successful Bash stdout.
