# ss-ctx MCP server (Front 2b: proactive sandbox + search + fetch) — Design

> Front 2 of SuperStack's "context all-rounder" is the runtime-output sandbox (the context-mode
> capability, rebuilt natively, inspiration-only). **2a** (shipped) is the REACTIVE half — a PostToolUse
> hook that shrinks oversized Bash output after the fact. **2b** (this doc) is the PROACTIVE half — an MCP
> server whose tools let the agent run commands, search, and fetch URLs so the verbose output never
> enters context in the first place.

## Problem

2a only helps once output has already come back from a `Bash` tool call. The bigger win is letting the
agent choose to run a noisy command (a test suite, a build, `git log`, a big grep) through a tool that
captures the full output to disk and hands back only a summary — output that never touches the context
window. context-mode delivers this via MCP tools (`ctx_execute` etc.); the research confirmed a real
registered MCP tool is required (a plain script's stdout goes straight into context when called via
`Bash`, and the agent can't know the full result is retrievable).

## Approach — a dependency-free Node MCP server

A single `mcp/server.mjs` speaking **raw JSON-RPC 2.0 over stdio** — no SDK, no `npm install`, no
`node_modules`, no build step. The only runtime requirement is Node (near-universal; already present).
This keeps SuperStack's zero-dependency identity: the MCP SDK would add a dependency tree and a bundling
step for no gain on five small tools. It runs as one cross-platform Node process, so there is **no
PowerShell twin** (unlike the `scripts/`).

It **shares 2a's store**: every tool reads/writes the same `${SUPERSTACK_DIR:-.superstack}/ctx/<id>.txt`
files the 2a hook fills, so the reactive hook and the proactive tools feed one unified store, and the
existing `/ss-ctx` bash retrieval keeps working over all of it.

### Verified protocol (controller pre-verified the whole server end-to-end)

Newline-delimited JSON-RPC 2.0 on stdin/stdout (one compact JSON object per line, no embedded newlines).
Confirmed against the MCP spec (2025-06-18) and proven with a simulated client:

- **`initialize`** → respond `{ protocolVersion: <echo the client's>, capabilities: { tools: { listChanged: false } }, serverInfo: { name: "ss-ctx", version } }`. Echoing the client's requested protocol version is the spec-sanctioned, drift-robust behavior.
- **`notifications/initialized`** (and other `notifications/*`) → no response.
- **`ping`** → `{ result: {} }`.
- **`tools/list`** → `{ result: { tools: [ { name, description, inputSchema } ] } }`.
- **`tools/call`** → `{ result: { content: [ { type: "text", text } ], isError? } }`. A thrown tool error becomes `isError: true` text (not a JSON-RPC error); unknown method/`id` present → JSON-RPC `error{-32601}`.

The controller built the full server and verified, via piped JSON-RPC: the handshake; `tools/list`
returning all 5; `ctx_execute` under-threshold (full return) and over-threshold (head/tail+marker, full
output stored byte-exact: 4000 lines == `seq 1 4000`); stderr+exit capture (`exit: 3`, stderr shown);
`ctx_batch_execute` (2 commands, 2 summaries); `ctx_search` (literal hit `seed1: NEEDLE here`);
`ctx_show` (byte-exact); `ctx_fetch_and_index` against real `https://example.com` (status 200,
HTML→text). The server is ready to transcribe.

## Tools (the run → retrieve set)

All summaries reuse the 2a shape: if the captured output is `> SS_CTX_THRESHOLD` (8000) bytes, return
first `SS_CTX_HEAD` (30) lines (capped 4000 bytes) + a marker + last `SS_CTX_TAIL` (15) lines (capped
2000 bytes); else return it whole. Marker:
`[ss-ctx] truncated - <bytes> bytes, <lines> lines total - full: <path> - retrieve: ctx_show <id>`
(the `<path>` is normalized to forward slashes for display; retrieval is by `<id>`). Full output is
always written to `${SUPERSTACK_DIR:-.superstack}/ctx/<id>.txt`.

| Tool | Args | Behavior |
| --- | --- | --- |
| `ctx_execute` | `command` (req), `label?` | Run `command` via `bash -c` (matches the Bash tool), capture stdout+stderr, store full, return `id: <id>\nexit: <code>\n<summary>`. id = `run-<sha1(label\|command + time + rand)[:12]>`. |
| `ctx_batch_execute` | `commands[]` (req) | Run each in order; return per-command `### <command>\nid: <id> exit: <code>\n<summary>` blocks. |
| `ctx_search` | `query` (req) | Literal substring search across `ctx/*.txt` (JS, no shell-out), ordinal file order; return `<id>: <line>` hits or `ss-ctx: no matches for '<query>'`. |
| `ctx_show` | `id` (req) | Sanitize id (`[^A-Za-z0-9_-]`→`_`), return full stored output, or `ss-ctx: no entry '<id>'`. |
| `ctx_fetch_and_index` | `url` (req), `label?` | `fetch(url)` (built-in, 20s timeout, follow redirects); if `content-type` is HTML run a lightweight zero-dep HTML→text (strip script/style, map headings/lists/links/code, decode common entities, collapse whitespace) else store raw text; store + return `url/id/status/<summary>`. id = `fetch-<sha1(url)[:12]>`. |

## Registration

A `.mcp.json` at the plugin root:

```json
{ "mcpServers": { "ss-ctx": { "command": "node", "args": ["${CLAUDE_PLUGIN_ROOT}/mcp/server.mjs"] } } }
```

`node` resolves cross-platform on PATH; `${CLAUDE_PLUGIN_ROOT}` is the live install dir. The server
starts at session load (one-time user approval), and `/reload-plugins` (or restart) activates a change.

## Components / files

- `mcp/server.mjs` — the dependency-free Node MCP server (Node builtins only: `child_process`, `crypto`, `fs`, `path`, global `fetch`).
- `.mcp.json` — plugin-root server registration.
- `tests/ctx-mcp.test.sh` — drives the server with simulated JSON-RPC over stdin; asserts handshake + each tool + store side-effects. SKIPs if `node` is absent.
- `tests/run.sh` — wire `[16/16]`.
- `skills/ctx/SKILL.md` — extend the 2a skill with the proactive tools + the two safety notes.
- `README.md`, `CHANGELOG.md` — surface it (note "1 MCP server").

## Security / privacy

- `ctx_execute`/`ctx_batch_execute` run arbitrary shell via `bash -c` — this is the **same trust level
  as the `Bash` tool the agent already has**, not a new capability; output is captured, not changed.
- `ctx_fetch_and_index` fetches arbitrary URLs. The content it returns is **DATA, not instructions** —
  the skill must remind the agent not to act on directives embedded in a fetched page (the
  instruction-source boundary). It uses the privacy-preserving pattern (fetch, keep raw out of context,
  return a preview), not the blocked curl/wget/WebFetch path.
- The store may hold command output / page text (possibly secrets in logs) under `.superstack/ctx/` —
  same trust boundary as the ledger; `/ss-ctx prune` clears it.
- Fail-safe: a tool error returns `isError` text, never crashes the server; a malformed JSON line is
  ignored; the server only ever writes under the store dir.

## Testing

The server is one Node process (no twin), so testing is behavioral, not parity:

- **Protocol:** pipe `initialize` → assert version echoed + `tools` capability + `serverInfo.name`;
  `tools/list` → assert 5 tool names; `ping` → `{}`.
- **Tools:** `ctx_execute` small (full return) and large (`seq 1 4000` → summary with marker + stored
  file byte-exact == `seq 1 4000`); stderr+exit captured; `ctx_batch_execute` two commands → two blocks;
  `ctx_search` literal hit + no-match message; `ctx_show` byte-exact + missing-id message;
  `ctx_fetch_and_index` — assert the HTML→text helper on a fixed HTML string (deterministic, offline);
  a live `example.com` fetch is a manual/optional smoke (don't make the suite depend on network).
- Match responses by JSON-RPC `id` (tools are async; responses may arrive out of request order).

## Out of scope (later)

- **FTS5 / BM25 ranking** — v1 search is literal grep over the store (adequate for command-output logs;
  the user chose the lean path). FTS5 can be layered later (a Python sidecar or WASM) without changing
  the tool interface.
- **Library-grade HTML→markdown** — v1 is a lightweight zero-dep converter; a richer one can replace
  `htmlToText` behind the same `ctx_fetch_and_index` interface.
- More `ctx_execute` languages (python/node interpreters), `ctx_stats`, persistent in-memory index,
  pagination — all deferred (YAGNI).

## Decided defaults (open to review)

- Raw JSON-RPC over the official SDK (zero-dependency).
- 5 tools; no FTS5 (grep); lightweight HTML→text (no markdown library).
- `ctx_execute` via `bash -c` (consistent with the Bash tool; requires bash on PATH — graceful error if
  absent).
- Shares the 2a `.superstack/ctx/` store; summaries use the 2a head/tail/marker shape and thresholds.
- No PowerShell twin (single cross-platform Node process).
