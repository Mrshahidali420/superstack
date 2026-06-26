# ss-munch — symbol-level code retrieval (Front 3) — Design

> Front 3 of SuperStack's "context all-rounder" rebuilds the **code-retrieval** capability of jcodemunch
> (jgravelle) natively, inspiration-only. Where Front 2 (`ss-ctx`) keeps *runtime output* out of context,
> `ss-munch` keeps *source code* out of context: it lets the agent read a **single symbol** (a function /
> class / method by name) or a **file outline** instead of a whole file — so exploring code costs tens of
> lines, not thousands.

## Problem

The agent's default way to understand code is `Read` (whole file) + `Grep` (matching lines). For a large
file you only needed one function from, `Read` burns the whole file into context; `Grep` finds the line
but not the symbol's bounds. Tool results are already 49–73% of tokens in agentic sessions, and reading
big source files is a top contributor. `ss-munch` returns *exactly the symbol asked for* (or a compact map
of a file's symbols), parsed from a real AST so the bounds are correct.

Unlike `ss-ctx`, **ss-munch output is small by design** (one symbol, or an outline), so the small result
entering context is the intended win — this is the inverse of the `ss-ctx` "keep big output out" problem.

## Approach — a second, dependency-vendored Node MCP server

A new `mcp/munch/server.mjs` speaking the **same raw JSON-RPC 2.0 over stdio** skeleton as the `ss-ctx`
server (`initialize` echoes the client protocol version; `ping` → `{}`; `notifications/*` → no response;
`tools/list`; `tools/call` → `content:[{type:text}]`/`isError`; unknown method+id → `-32601`; never-crash
`uncaughtException`/`unhandledRejection` → stderr; newline-delimited, one JSON object per line). It is
registered as a **second** MCP server (`ss-munch`) alongside `ss-ctx` in `.mcp.json`.

**Why a separate server (not new tools on the `ss-ctx` server):** the `ss-ctx` server is *dependency-free*
(Node builtins only) — a stated virtue. `ss-munch` needs a parser (vendored WASM). Keeping it separate
preserves `ss-ctx`'s purity and isolates the binary payload. README count → **2 MCP servers**.

### Proven mechanism (controller spike — parse + extract end-to-end)

Proven on Windows 11 + Node 24 by a controller spike (obtain the files via a throwaway npm install, then
**load + parse + extract from the on-disk `.wasm` files in plain Node**, no SDK/bundler). The plan stage
re-verifies the same works from the *copied* `mcp/munch/vendor/` dir loaded by the `.mjs` server
(`createRequire`) — that copy-and-load step is the one piece the spike obtained from `node_modules`:

- **Runtime:** `web-tree-sitter@0.20.8` — a single CJS loader `tree-sitter.js` + `tree-sitter.wasm`
  (182 KB). Loaded via `const Parser = require('<vendor>/tree-sitter.js')` (from a `.mjs` server using
  `createRequire(import.meta.url)`); `await Parser.init({ locateFile: (f) => '<vendor>/' + f })`.
- **Grammars:** `tree-sitter-wasms@0.1.13` prebuilt per-language `.wasm`. Loaded with
  `await Parser.Language.load('<vendor>/grammars/tree-sitter-<lang>.wasm')`, then
  `parser.setLanguage(lang)`.
- **The version pairing is load-bearing:** runtime and grammars must be the **same tree-sitter ABI**.
  `tree-sitter-wasms` only ships **0.20-ABI** grammars (its build pins `tree-sitter-cli@^0.20.8`), so
  web-tree-sitter must be 0.20.x. (web-tree-sitter 0.26 + these grammars fails with a dylink ABI error —
  confirmed.) 0.20 grammars are fine for symbol extraction: the node types we use are long-stable and
  tree-sitter recovers from newer syntax it doesn't fully know.
- **Extraction proven:** parsing JS and Python, walking the AST, classifying `function_declaration` /
  `class_declaration` / `method_definition` / arrow-`variable_declarator` / Python
  `function_definition` / `class_definition`, and slicing a symbol's exact source by
  `[node.startIndex, node.endIndex]` — all confirmed against fixtures.

## Languages (v1) and vendoring

**Core 7** grammars are vendored (≈ 7.4 MB committed): **JavaScript** (632 KB), **TypeScript** (2.3 MB),
**TSX** (2.4 MB), **Python** (465 KB), **Go** (230 KB), **Rust** (800 KB), **Java** (420 KB) + runtime
182 KB. All seven upstream grammars are **MIT** (same family as the runtime) — clean for this MIT repo.

Files live under `mcp/munch/vendor/`:

```
mcp/munch/vendor/
  tree-sitter.js          # web-tree-sitter 0.20.8 loader (MIT)
  tree-sitter.wasm        # web-tree-sitter 0.20.8 runtime (MIT)
  grammars/
    tree-sitter-javascript.wasm  tree-sitter-typescript.wasm  tree-sitter-tsx.wasm
    tree-sitter-python.wasm  tree-sitter-go.wasm  tree-sitter-rust.wasm  tree-sitter-java.wasm
  README.md               # provenance: exact package@version, license per grammar, regen command
```

Adding a language later = drop a matching-ABI `.wasm` in `grammars/` and add a row to the language config.
Extension → language → grammar mapping is a single table (`.js`/`.jsx`→javascript, `.ts`→typescript,
`.tsx`→tsx, `.py`→python, `.go`→go, `.rs`→rust, `.java`→java).

## Tools (v1)

Each tool returns `content:[{type:text}]`. Grammars are loaded **lazily** (only when a tool first needs a
language) and cached for the process; parsed trees are cached in-memory keyed by `path+mtime` for the
session. No on-disk index.

| Tool | Args | Behavior |
| --- | --- | --- |
| `munch_outline` | `file` (req) | Parse `file` (language by extension), return one row per top-level symbol: `<startLine>-<endLine>  <kind>  <name><signature?>` (signature = parameter-list text when the grammar exposes it). Unsupported extension / parse failure → a clear message, never a crash. |
| `munch_symbol` | `file` (req), `name` (req) | Find the symbol named `name` in `file`; return its exact source (`code.slice(startIndex, endIndex)`) prefixed with `# <file>:<startLine>-<endLine>`. Multiple matches → list their locations and return the first (note the others). Not found → `ss-munch: no symbol '<name>' in <file>` plus a hint to run `munch_outline`. |
| `munch_search` | `name` (req), `path?` (default `.`) | Enumerate **git-tracked** files of supported extensions under `path` (`git ls-files`), parse on demand, return symbols whose name contains `name` (case-insensitive) as `<path>:<line>  <kind>  <name>`. Bounded: scan ≤ `SS_MUNCH_MAX_FILES` (2000) files, return ≤ `SS_MUNCH_MAX_HITS` (200) hits; if capped, append a `truncated — narrow the query or path` note. Re-parses each call (no index) — O(repo); fine for small/medium repos. |

Per-language symbol node types (the outline classifier):

- **JS / TS / TSX:** `function_declaration`, `generator_function_declaration`, `class_declaration`,
  `method_definition`, `variable_declarator` whose value is `arrow_function`/`function_expression`;
  TS adds `interface_declaration`, `type_alias_declaration`, `enum_declaration`.
- **Python:** `function_definition`, `class_definition` (unwrap `decorated_definition`).
- **Go:** `function_declaration`, `method_declaration`, `type_declaration`.
- **Rust:** `function_item`, `struct_item`, `enum_item`, `trait_item`, `impl_item`, `mod_item`.
- **Java:** `class_declaration`, `interface_declaration`, `enum_declaration`, `method_declaration`,
  `constructor_declaration`.

Name via `node.childForFieldName('name')`; for arrow-consts, the declarator's `name`. A small per-language
config object maps `{ extensions, grammarFile, symbolTypes, nameField }` so adding a language is data, not
code.

## Registration

`.mcp.json` gains a second server:

```json
{ "mcpServers": {
    "ss-ctx":   { "command": "node", "args": ["${CLAUDE_PLUGIN_ROOT}/mcp/server.mjs"] },
    "ss-munch": { "command": "node", "args": ["${CLAUDE_PLUGIN_ROOT}/mcp/munch/server.mjs"] }
} }
```

The server resolves its vendor dir relative to its own file (`import.meta.url`), so it works from the
live install dir.

## Components / files

- `mcp/munch/server.mjs` — the MCP server (JSON-RPC skeleton mirrored from `mcp/server.mjs`).
- `mcp/munch/extract.mjs` — the parse/outline/symbol/search core (the language config + AST walk), kept
  separate from the protocol layer so it's unit-testable without stdio.
- `mcp/munch/vendor/**` — the runtime + 7 grammars + provenance README.
- `.mcp.json` — add the `ss-munch` server.
- `skills/munch/SKILL.md` — name `ss-munch`; "read the symbol, not the file"; tool docs; links
  `[[ss-context]]` / `[[ss-ctx]]`; lineage (Front 3, the jcodemunch capability rebuilt natively).
- `skills/context/…` (Front-1 cockpit) — detect `ss-munch` in `.mcp.json` so the "code exploration" row
  reads `detected (native)` (small one-line addition to the existing `.mcp.json` grep).
- `tests/munch.test.sh` — behavioral: drive the server via piped JSON-RPC + a `tests/fixtures/munch/`
  dir with a small file per language; assert outline counts, a symbol body, a search hit, the unsupported
  /not-found messages, and the JSON-RPC handshake. SKIPs if `node` is absent.
- `tests/run.sh` — wire `[17/17]`.
- `README.md`, `CHANGELOG.md` — surface it (31 skills, **2 MCP servers**).

## Security / privacy

- ss-munch is **read-only**: it parses files and returns slices of them. It runs no user code, spawns no
  shell (except `git ls-files` for enumeration in `munch_search`), and writes nothing.
- It only reads files under the working tree (paths the agent already can `Read`); `munch_search` is
  bounded to git-tracked files, so it won't wander into `node_modules`/build dirs or untracked secrets.
- Parsed source may contain secrets (same as `Read`) — it stays in the agent's context, not persisted.
- Fail-safe: a tool error returns `isError` text; a malformed JSON line is ignored; a parse failure or
  unsupported extension returns a message, never a crash (the `ss-ctx` never-crash handlers are reused).

## Testing

One Node process (no PowerShell twin), so testing is behavioral + a unit test of `extract.mjs`:

- **Protocol:** `initialize` echoes version + `tools` capability + `serverInfo.name = "ss-munch"`;
  `tools/list` → the 3 tool names; `ping` → `{}`; unknown method → `-32601`; notification → no output.
- **Tools, over `tests/fixtures/munch/`:** `munch_outline` on a JS fixture returns the expected symbol
  rows (function/arrow/class/method); `munch_symbol(file, name)` returns the exact body; `munch_search`
  finds a name across two fixture files and reports `path:line`; unsupported extension + not-found
  symbol return their messages. A Python and a Go fixture prove cross-language.
- Match responses by JSON-RPC `id` (async; out-of-order possible).

## Out of scope (v1, deferred)

- **On-disk symbol index** (SQLite/sql.js) — only `munch_search` benefits; parse-on-demand is adequate
  for v1. The index is the v2 speed-up (search becomes O(changed files)).
- **Incremental file-watching**, **call-graph / references**, **semantic/embedding search**.
- **Languages beyond the Core 7** — additive later (drop a 0.20-ABI `.wasm` + a config row).
- **Modern (0.25+) grammars** — would need a different prebuilt source or a build step; 0.20 is adequate
  for symbol extraction. Revisit if newer-syntax mis-parsing shows up in practice.
- **A PowerShell twin** — none; it's one cross-platform Node process (like `ss-ctx`).

## Decided defaults (open to review)

- A **second** MCP server `ss-munch`, separate from `ss-ctx`, so `ss-ctx` stays dependency-free.
- **web-tree-sitter 0.20.8 + tree-sitter-wasms 0.1.13**, vendored (proven matched ABI); **Core 7**
  languages (~7.4 MB).
- **Parse-on-demand, no index;** in-memory tree cache per session; lazy per-language grammar load.
- 3 tools: `munch_outline`, `munch_symbol`, `munch_search` (search bounded + capped, no store-offload).
- Protocol/never-crash skeleton reused verbatim from `mcp/server.mjs`.
