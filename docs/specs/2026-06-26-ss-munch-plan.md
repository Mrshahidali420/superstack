# ss-munch — symbol-level code retrieval (Front 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a second, dependency-vendored Node MCP server (`ss-munch`) that returns a single code symbol (function/class/method by name) or a compact file outline instead of a whole file — so exploring code costs tens of lines, not thousands.

**Architecture:** A new `mcp/munch/server.mjs` speaks the same raw JSON-RPC 2.0 over stdio as the `ss-ctx` server, but delegates parsing to `mcp/munch/extract.mjs`, which loads a vendored `web-tree-sitter` runtime + per-language grammar `.wasm` files (zero-install, via `createRequire`) and walks the AST. It registers as a **second** MCP server alongside `ss-ctx`, keeping `ss-ctx` dependency-free.

**Tech Stack:** Node (builtins + vendored `web-tree-sitter@0.20.8` WASM), `tree-sitter-wasms@0.1.13` grammars (0.20 ABI), bash test harness driving JSON-RPC over stdio.

## Global Constraints

Every task's requirements implicitly include this section. Values are copied verbatim from the spec and from the plan-stage pre-verification (which proved all of the below on Windows 11 + Node 24).

- **Runtime/grammar ABI pairing is load-bearing:** `web-tree-sitter@0.20.8` (files `vendor/tree-sitter.js` + `vendor/tree-sitter.wasm`) **must** pair with `tree-sitter-wasms@0.1.13` grammars (`vendor/grammars/tree-sitter-<lang>.wasm`). Both are tree-sitter **0.20 ABI**. web-tree-sitter 0.26 + these grammars fails with a dylink ABI error — do **not** "upgrade" the runtime.
- **Zero-install load:** `extract.mjs` loads the CJS runtime via `createRequire(import.meta.url)` from `./vendor/tree-sitter.js`, and `Parser.init({ locateFile: (f) => path.join(VENDOR, f) })`. No `npm install`, no `node_modules`, no bundler. The vendor dir is resolved relative to `extract.mjs`'s own `import.meta.url` so it works from the live install dir.
- **Core 7 languages only (v1).** Extension → grammar map: `.js`/`.jsx`/`.mjs`/`.cjs`→`javascript`, `.ts`/`.mts`/`.cts`→`typescript`, `.tsx`→`tsx`, `.py`/`.pyi`→`python`, `.go`→`go`, `.rs`→`rust`, `.java`→`java`.
- **One Parser per language, cached for the process lifetime.** A per-call `new Parser()` leaks WASM handles (unbounded growth in a long-running server) and triggers a libuv `UV_HANDLE_CLOSING` abort on process exit. `parser.parse()` is synchronous after the grammar `await`, so a cached parser is concurrency-safe.
- **Teardown = natural event-loop drain.** The server exits when stdin closes by letting the loop drain (no explicit handler needed; the WASM runtime does not pin the loop open). **Never call `process.exit()` after WASM work** — it force-tears-down libuv mid-close and aborts (exit 127) on Windows. **Any Node test harness must use `process.exitCode = N`, never `process.exit()`.**
- **Path handling:** the server resolves relative paths against its cwd and handles Windows-absolute paths; it can **not** resolve Git-Bash `/c/...`-style absolutes (Node `existsSync` rejects them on Windows). Tests therefore pass repo-relative paths after `cd "$ROOT"`, never `/c/...` absolutes.
- **Protocol skeleton reused verbatim from `mcp/server.mjs`:** `initialize` echoes `params.protocolVersion` (default `2025-06-18`) + `capabilities.tools` + `serverInfo.name = "ss-munch"`; `ping` → `{}`; `notifications/*` → no response; `tools/list` → the 3 tools; `tools/call` → `content:[{type:text}]` or `isError`; unknown method **with id** → error `-32601`; never-crash `uncaughtException`/`unhandledRejection` → stderr (never stdout); newline-delimited buffer loop, one JSON object per line; malformed JSON line ignored.
- **Caps:** `SS_MUNCH_MAX_FILES=2000`, `SS_MUNCH_MAX_HITS=200` (env-overridable).
- **Read-only:** parses files and returns slices; runs no user code; spawns only `git ls-files` (for `munch_search`); writes nothing.
- **Output formats (verbatim):**
  - outline row: `<startLine>-<endLine>  <kind>  <name><signature?>` (two spaces between fields; signature, when present, is its parameter-list text with leading space, internal whitespace collapsed).
  - symbol: `# <file>:<startLine>-<endLine>\n<exact source slice>`; multiple matches joined by a blank line.
  - search hit: `<path>:<startLine>  <kind>  <name>`.
  - not found: `ss-munch: symbol '<name>' not found in <file>` (+ hint to run `munch_outline`).
  - unsupported extension: `ss-munch: unsupported file type: <file>`.
  - missing file: `ss-munch: no such file: <file>`.
  - search cap note (appended line): `[ss-munch] truncated at <N> hits` or `[ss-munch] scanned first <N> of <M> files`.
- **Commits:** conventional-commit format; **no AI attribution** (disabled globally).

---

### Task 1: Vendor the runtime + 7 grammars + provenance README

The 9 binary files are obtained from `web-tree-sitter@0.20.8` (its `tree-sitter.js` + `tree-sitter.wasm`) and `tree-sitter-wasms@0.1.13` (its `out/tree-sitter-<lang>.wasm`). They are already staged under `mcp/munch/vendor/` from the plan-stage pre-verification. This task confirms them, writes provenance, and proves a zero-install load.

**Files:**
- Create: `mcp/munch/vendor/tree-sitter.js` (web-tree-sitter 0.20.8 loader, ~72 KB)
- Create: `mcp/munch/vendor/tree-sitter.wasm` (web-tree-sitter 0.20.8 runtime, ~182 KB)
- Create: `mcp/munch/vendor/grammars/tree-sitter-{javascript,typescript,tsx,python,go,rust,java}.wasm` (7 files, ~7.2 MB total)
- Create: `mcp/munch/vendor/README.md` (provenance)

**Interfaces:**
- Produces: the `vendor/` tree that `extract.mjs` (Task 2) loads via `createRequire` + `Parser.Language.load`.

- [ ] **Step 1: Confirm all 9 binaries are present with sane sizes**

Run:
```bash
cd "$(git rev-parse --show-toplevel)"
ls -1 mcp/munch/vendor/tree-sitter.js mcp/munch/vendor/tree-sitter.wasm
ls -1 mcp/munch/vendor/grammars/tree-sitter-*.wasm | wc -l
```
Expected: both runtime files listed; grammar count = `7`. (If absent, obtain via a throwaway `npm install web-tree-sitter@0.20.8 tree-sitter-wasms@0.1.13` in a scratch dir and copy `node_modules/web-tree-sitter/tree-sitter.{js,wasm}` + `node_modules/tree-sitter-wasms/out/tree-sitter-<lang>.wasm` for the Core 7.)

- [ ] **Step 2: Write the provenance README**

Create `mcp/munch/vendor/README.md`:
```markdown
# ss-munch vendored parser (web-tree-sitter 0.20 ABI)

Zero-install: loaded directly by `../extract.mjs` via `createRequire` — no npm install, no node_modules.

## Runtime
- `tree-sitter.js`, `tree-sitter.wasm` — **web-tree-sitter@0.20.8** (MIT).

## Grammars (`grammars/`)
All from **tree-sitter-wasms@0.1.13** (prebuilt, **0.20 ABI** — its build pins `tree-sitter-cli@^0.20.8`). Each upstream grammar is **MIT**:
- `tree-sitter-javascript.wasm`  (tree-sitter/tree-sitter-javascript, MIT)
- `tree-sitter-typescript.wasm`  (tree-sitter/tree-sitter-typescript, MIT)
- `tree-sitter-tsx.wasm`         (tree-sitter/tree-sitter-typescript, MIT)
- `tree-sitter-python.wasm`      (tree-sitter/tree-sitter-python, MIT)
- `tree-sitter-go.wasm`          (tree-sitter/tree-sitter-go, MIT)
- `tree-sitter-rust.wasm`        (tree-sitter/tree-sitter-rust, MIT)
- `tree-sitter-java.wasm`        (tree-sitter/tree-sitter-java, MIT)

## ABI pairing is load-bearing
Runtime and grammars must share the tree-sitter ABI generation. web-tree-sitter 0.26 + these 0.20 grammars
fails with a dylink ABI error. Do not bump the runtime without re-vendoring matching-ABI grammars.

## Regenerate
    npm install web-tree-sitter@0.20.8 tree-sitter-wasms@0.1.13
    cp node_modules/web-tree-sitter/tree-sitter.js   tree-sitter.js
    cp node_modules/web-tree-sitter/tree-sitter.wasm tree-sitter.wasm
    for g in javascript typescript tsx python go rust java; do
      cp node_modules/tree-sitter-wasms/out/tree-sitter-$g.wasm grammars/tree-sitter-$g.wasm
    done
```

- [ ] **Step 3: Prove a zero-install load from the vendor dir**

Run (the `.cjs` extension forces CommonJS so `require` of the vendored loader works in a one-off check):
```bash
cd "$(git rev-parse --show-toplevel)/mcp/munch"
node -e '
const path=require("path");
const Parser=require("./vendor/tree-sitter.js");
(async()=>{
  await Parser.init({locateFile:f=>path.join("vendor",f)});
  const L=await Parser.Language.load("vendor/grammars/tree-sitter-javascript.wasm");
  const p=new Parser(); p.setLanguage(L);
  const t=p.parse("function f(){}");
  console.log("ROOT", t.rootNode.type);
})().catch(e=>{console.error("LOAD_FAIL",e);process.exitCode=1;});
'
```
Expected: `ROOT program` (and exit 0). A `LOAD_FAIL` with a dylink/ABI error means the runtime↔grammar ABI is mismatched — re-vendor per Step 2.

- [ ] **Step 4: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add mcp/munch/vendor
git commit -m "feat(ss-munch): vendor web-tree-sitter 0.20.8 runtime + Core 7 grammars"
```

---

### Task 2: `extract.mjs` — language config + AST-walk extraction core

The parse/outline/symbol/search core, kept separate from the protocol layer so it is unit-testable without stdio. Also create the per-language fixtures used by this task and Task 4.

**Files:**
- Create: `mcp/munch/extract.mjs`
- Create: `tests/fixtures/munch/calc.js`, `shapes.ts`, `app.tsx`, `util.py`, `main.go`, `lib.rs`, `Foo.java`

**Interfaces:**
- Consumes: `mcp/munch/vendor/**` (Task 1).
- Produces (imported by `server.mjs` in Task 3 and the test in Task 4):
  - `EXT_TO_LANG: Record<string,string>` — extension (lowercased, with dot) → grammar key.
  - `detectLang(filePath: string): string | null` — grammar key or null.
  - `extractOutline(code: string, langKey: string): Promise<Symbol[]>` where `Symbol = { kind: string, name: string, signature: string, startLine: number, endLine: number, startIndex: number, endIndex: number }` (1-based lines; byte offsets into `code`).
  - `findSymbols(code: string, langKey: string, name: string): Promise<Symbol[]>` — exact-name matches.
  - `getLanguage(key: string): Promise<Language>` — lazy, cached grammar load.

- [ ] **Step 1: Create the per-language fixtures**

Create `tests/fixtures/munch/calc.js`:
```javascript
export function alpha(a, b) { return a + b; }
export const beta = (x) => x * 2;
class Gamma {
  doThing() { return 1; }
}
function* gen() { yield 1; }
```
Create `tests/fixtures/munch/shapes.ts`:
```typescript
interface Shape { area(): number; }
type ID = string | number;
enum Color { Red, Green }
export function area(s: Shape): number { return s.area(); }
const make = (n: number): ID => `${n}`;
class Circle implements Shape { area() { return 3.14; } }
```
Create `tests/fixtures/munch/app.tsx`:
```tsx
interface Props { title: string; }
export const Card = (props: Props) => <div>{props.title}</div>;
function App() { return <Card title="x" />; }
```
Create `tests/fixtures/munch/util.py`:
```python
import functools
def alpha(a, b):
    return a + b
class Gamma:
    def do_thing(self):
        return 1
@functools.cache
def cached(n):
    return n
```
Create `tests/fixtures/munch/main.go`:
```go
package main
type Shape interface { Area() float64 }
type Circle struct { r float64 }
func (c Circle) Area() float64 { return 3.14 }
func Alpha(a int, b int) int { return a + b }
```
Create `tests/fixtures/munch/lib.rs`:
```rust
struct Point { x: i32, y: i32 }
enum Dir { N, S }
trait Greet { fn hello(&self); }
impl Greet for Point { fn hello(&self) {} }
mod inner { pub fn helper() {} }
fn alpha(a: i32, b: i32) -> i32 { a + b }
```
Create `tests/fixtures/munch/Foo.java`:
```java
public class Foo {
    private int x;
    public Foo(int x) { this.x = x; }
    public int getX() { return x; }
}
interface Bar { void run(); }
enum Color { RED, GREEN }
```

- [ ] **Step 2: Write the failing test**

Create the throwaway check `tests/fixtures/munch/_extract_check.mjs` (deleted in Step 5 — it is folded into `tests/munch.test.sh` in Task 4):
```javascript
import { pathToFileURL } from 'node:url';
const url = pathToFileURL(process.argv[2]).href;   // absolute path to mcp/munch/extract.mjs
const { extractOutline, findSymbols, detectLang } = await import(url);

const CASES = {
  javascript: ['tests/fixtures/munch/calc.js', ['alpha','beta','Gamma','doThing','gen']],
  typescript: ['tests/fixtures/munch/shapes.ts', ['Shape','ID','Color','area','make','Circle']],
  tsx:        ['tests/fixtures/munch/app.tsx',  ['Props','Card','App']],
  python:     ['tests/fixtures/munch/util.py',  ['alpha','Gamma','do_thing','cached']],
  go:         ['tests/fixtures/munch/main.go',  ['Shape','Circle','Area','Alpha']],
  rust:       ['tests/fixtures/munch/lib.rs',   ['Point','Dir','Greet','alpha','inner','helper']],
  java:       ['tests/fixtures/munch/Foo.java', ['Foo','getX','Bar','run','Color']],
};
const { readFileSync } = await import('node:fs');
let fail = 0;
for (const [lang, [file, expect]] of Object.entries(CASES)) {
  const code = readFileSync(file, 'utf8');
  if (detectLang(file) !== lang) { console.log(`FAIL detect ${file}`); fail++; }
  const names = (await extractOutline(code, lang)).map(s => s.name);
  const missing = expect.filter(n => !names.includes(n));
  if (missing.length) { console.log(`FAIL ${lang} missing: ${missing.join(',')}`); fail++; }
  // byte-offset slice of the first expected symbol must be non-empty and start sensibly
  const hit = (await findSymbols(code, lang, expect[0]))[0];
  if (!hit || !code.slice(hit.startIndex, hit.endIndex).includes(expect[0])) { console.log(`FAIL ${lang} slice ${expect[0]}`); fail++; }
}
console.log(fail === 0 ? 'EXTRACT_OK' : `EXTRACT_FAIL(${fail})`);
process.exitCode = fail === 0 ? 0 : 1;   // NEVER process.exit() after WASM work
```

Run:
```bash
cd "$(git rev-parse --show-toplevel)"
node tests/fixtures/munch/_extract_check.mjs "$PWD/mcp/munch/extract.mjs"
```
Expected: FAIL — `Cannot find module '.../mcp/munch/extract.mjs'` (not yet created).

- [ ] **Step 3: Implement `mcp/munch/extract.mjs`**

Create `mcp/munch/extract.mjs`:
```javascript
// SPDX-License-Identifier: MIT
// ss-munch symbol extraction: web-tree-sitter (0.20 ABI) loaded zero-install from
// the vendored runtime + grammars next to this file. No npm install, no node_modules.
//
// The runtime (vendor/tree-sitter.js + tree-sitter.wasm) and the grammars
// (vendor/grammars/tree-sitter-<lang>.wasm) MUST share the same tree-sitter ABI
// generation. We pin web-tree-sitter 0.20.8 against tree-sitter-wasms 0.1.13 (0.20 ABI).

import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const VENDOR = path.join(__dirname, 'vendor');
const require = createRequire(import.meta.url);

// vendor/tree-sitter.js is CommonJS (0.20.8) — load it through createRequire.
const Parser = require(path.join(VENDOR, 'tree-sitter.js'));

// --- file extension -> grammar key -------------------------------------------

export const EXT_TO_LANG = {
  '.js': 'javascript', '.jsx': 'javascript', '.mjs': 'javascript', '.cjs': 'javascript',
  '.ts': 'typescript', '.mts': 'typescript', '.cts': 'typescript',
  '.tsx': 'tsx',
  '.py': 'python', '.pyi': 'python',
  '.go': 'go',
  '.rs': 'rust',
  '.java': 'java',
};

export function detectLang(filePath) {
  return EXT_TO_LANG[path.extname(filePath).toLowerCase()] || null;
}

// --- per-language node-type -> symbol kind -----------------------------------

const JS_KINDS = {
  function_declaration: 'function',
  generator_function_declaration: 'function',
  class_declaration: 'class',
  method_definition: 'method',
};
const TS_KINDS = {
  ...JS_KINDS,
  abstract_class_declaration: 'class',
  interface_declaration: 'interface',
  type_alias_declaration: 'type',
  enum_declaration: 'enum',
};
const PY_KINDS = {
  function_definition: 'function',
  class_definition: 'class',
};
const GO_KINDS = {
  function_declaration: 'function',
  method_declaration: 'method',
  type_spec: 'type',
};
const RUST_KINDS = {
  function_item: 'function',
  struct_item: 'struct',
  enum_item: 'enum',
  trait_item: 'trait',
  impl_item: 'impl',
  mod_item: 'module',
};
const JAVA_KINDS = {
  class_declaration: 'class',
  interface_declaration: 'interface',
  enum_declaration: 'enum',
  method_declaration: 'method',
  constructor_declaration: 'constructor',
};

const LANG_KINDS = {
  javascript: JS_KINDS,
  typescript: TS_KINDS,
  tsx: TS_KINDS,
  python: PY_KINDS,
  go: GO_KINDS,
  rust: RUST_KINDS,
  java: JAVA_KINDS,
};

const JS_LIKE = new Set(['javascript', 'typescript', 'tsx']);

// --- lazy runtime + grammar loading ------------------------------------------

let initPromise = null;
function init() {
  if (!initPromise) {
    initPromise = Parser.init({ locateFile: (f) => path.join(VENDOR, f) });
  }
  return initPromise;
}

const langCache = new Map();
export async function getLanguage(key) {
  if (langCache.has(key)) return langCache.get(key);
  await init();
  const lang = await Parser.Language.load(
    path.join(VENDOR, 'grammars', `tree-sitter-${key}.wasm`),
  );
  langCache.set(key, lang);
  return lang;
}

// One Parser per language, reused for the process lifetime. Creating a new
// Parser per call leaks WASM handles — unbounded growth in a long-running
// server, and a libuv teardown abort on Windows. parse() is synchronous after
// the grammar await, so a cached parser is safe under serial or interleaved calls.
const parserCache = new Map();
async function getParser(key) {
  if (parserCache.has(key)) return parserCache.get(key);
  const lang = await getLanguage(key);
  const parser = new Parser();
  parser.setLanguage(lang);
  parserCache.set(key, parser);
  return parser;
}

// --- AST walk + classification ------------------------------------------------

function* walk(node) {
  yield node;
  for (let i = 0; i < node.childCount; i++) {
    const c = node.child(i);
    if (c) yield* walk(c);
  }
}

function signatureOf(node) {
  const params = node?.childForFieldName?.('parameters');
  return params ? params.text.replace(/\s+/g, ' ') : '';
}

// Returns { kind, name, sigNode } or null.
function classify(node, langKey) {
  const t = node.type;

  // const fn = () => ... / const fn = function () { ... }
  if (JS_LIKE.has(langKey) && t === 'variable_declarator') {
    const value = node.childForFieldName('value');
    if (value && (value.type === 'arrow_function' || value.type === 'function_expression')) {
      const name = node.childForFieldName('name')?.text;
      if (name) return { kind: 'function', name, sigNode: value };
    }
    return null;
  }

  const kind = LANG_KINDS[langKey]?.[t];
  if (!kind) return null;

  // impl blocks have no `name`; identify by the type (and trait) they implement.
  if (langKey === 'rust' && t === 'impl_item') {
    const typeText = node.childForFieldName('type')?.text;
    const traitText = node.childForFieldName('trait')?.text;
    if (!typeText) return null;
    return { kind, name: traitText ? `${traitText} for ${typeText}` : typeText, sigNode: null };
  }

  const name = node.childForFieldName('name')?.text;
  if (!name) return null;
  return { kind, name, sigNode: node };
}

// Decorated Python defs: report the range that includes the decorators.
function rangeNodeFor(node, langKey) {
  if (langKey === 'python' && node.parent?.type === 'decorated_definition') {
    return node.parent;
  }
  return node;
}

/**
 * Extract all symbols from source. Returns:
 * [{ kind, name, signature, startLine, endLine, startIndex, endIndex }]
 */
export async function extractOutline(code, langKey) {
  const parser = await getParser(langKey);
  const tree = parser.parse(code);
  const out = [];
  try {
    for (const node of walk(tree.rootNode)) {
      const c = classify(node, langKey);
      if (!c) continue;
      const rn = rangeNodeFor(node, langKey);
      out.push({
        kind: c.kind,
        name: c.name,
        signature: signatureOf(c.sigNode),
        startLine: rn.startPosition.row + 1,
        endLine: rn.endPosition.row + 1,
        startIndex: rn.startIndex,
        endIndex: rn.endIndex,
      });
    }
  } finally {
    tree.delete?.();
  }
  return out;
}

/**
 * Find symbols by exact name (all matches — handles overloads / duplicate names).
 */
export async function findSymbols(code, langKey, name) {
  const syms = await extractOutline(code, langKey);
  return syms.filter((s) => s.name === name);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
cd "$(git rev-parse --show-toplevel)"
node tests/fixtures/munch/_extract_check.mjs "$PWD/mcp/munch/extract.mjs"
```
Expected: `EXTRACT_OK` and exit 0 (all 7 languages extract the expected symbols; first-symbol byte-slices are valid).

- [ ] **Step 5: Remove the throwaway check and commit**

```bash
cd "$(git rev-parse --show-toplevel)"
rm tests/fixtures/munch/_extract_check.mjs
git add mcp/munch/extract.mjs tests/fixtures/munch
git commit -m "feat(ss-munch): symbol extraction core + per-language fixtures"
```

---

### Task 3: `server.mjs` — JSON-RPC stdio server + 3 tools

Mirror the `mcp/server.mjs` skeleton (protocol + never-crash handlers + buffer loop) and wire the 3 tools to `extract.mjs`.

**Files:**
- Create: `mcp/munch/server.mjs`

**Interfaces:**
- Consumes: `./extract.mjs` — `detectLang`, `extractOutline`, `findSymbols`, `EXT_TO_LANG`.
- Produces: an stdio MCP server exposing `munch_outline(file)`, `munch_symbol(file, name)`, `munch_search(name, path?)`.

- [ ] **Step 1: Write the failing smoke test**

Run (server does not exist yet):
```bash
cd "$(git rev-parse --show-toplevel)"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"munch_outline","arguments":{"file":"tests/fixtures/munch/calc.js"}}}' \
  | node mcp/munch/server.mjs
```
Expected: FAIL — `Cannot find module '.../mcp/munch/server.mjs'`.

- [ ] **Step 2: Implement `mcp/munch/server.mjs`**

Create `mcp/munch/server.mjs`:
```javascript
#!/usr/bin/env node
// SPDX-License-Identifier: MIT
// ss-munch MCP server (Front 3): raw JSON-RPC 2.0 over stdio, mirroring the ss-ctx
// skeleton. Delegates parsing to ./extract.mjs (vendored web-tree-sitter, zero-install).
// Tools: munch_outline, munch_symbol, munch_search. Read-only; shells only `git ls-files`.
import { readFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { detectLang, extractOutline, findSymbols, EXT_TO_LANG } from './extract.mjs';

const MAX_FILES = parseInt(process.env.SS_MUNCH_MAX_FILES || '2000', 10);
const MAX_HITS = parseInt(process.env.SS_MUNCH_MAX_HITS || '200', 10);

const fmtRow = (s) =>
  `${s.startLine}-${s.endLine}  ${s.kind}  ${s.name}${s.signature ? ' ' + s.signature : ''}`;

async function munchOutline(file) {
  const lang = detectLang(file);
  if (!lang) return `ss-munch: unsupported file type: ${file}`;
  if (!existsSync(file)) return `ss-munch: no such file: ${file}`;
  const syms = await extractOutline(readFileSync(file, 'utf8'), lang);
  return syms.length ? syms.map(fmtRow).join('\n') : `ss-munch: no symbols in ${file}`;
}

async function munchSymbol(file, name) {
  const lang = detectLang(file);
  if (!lang) return `ss-munch: unsupported file type: ${file}`;
  if (!existsSync(file)) return `ss-munch: no such file: ${file}`;
  const code = readFileSync(file, 'utf8');
  const hits = await findSymbols(code, lang, name);
  if (!hits.length) return `ss-munch: symbol '${name}' not found in ${file}\n(run munch_outline ${file} to list symbols)`;
  return hits
    .map((s) => `# ${file}:${s.startLine}-${s.endLine}\n${code.slice(s.startIndex, s.endIndex)}`)
    .join('\n\n');
}

function listFiles(root) {
  try {
    return execFileSync('git', ['ls-files'], { cwd: root, encoding: 'utf8', maxBuffer: 1 << 24 })
      .split('\n')
      .filter(Boolean);
  } catch {
    return null;
  }
}

async function munchSearch(name, searchPath) {
  const root = searchPath || '.';
  const files = listFiles(root);
  if (files === null) return `ss-munch: not a git repository (or git unavailable): ${root}`;
  const needle = name.toLowerCase();
  const supported = files.filter((f) => EXT_TO_LANG[path.extname(f).toLowerCase()]);
  const truncatedFiles = supported.length > MAX_FILES;
  const hits = [];
  for (const rel of supported.slice(0, MAX_FILES)) {
    if (hits.length >= MAX_HITS) break;
    let code;
    try { code = readFileSync(path.join(root, rel), 'utf8'); } catch { continue; }
    let syms;
    try { syms = await extractOutline(code, detectLang(rel)); } catch { continue; }
    for (const s of syms) {
      if (s.name.toLowerCase().includes(needle)) {
        hits.push(`${rel}:${s.startLine}  ${s.kind}  ${s.name}`);
        if (hits.length >= MAX_HITS) break;
      }
    }
  }
  if (!hits.length) return `ss-munch: no symbol matching '${name}'`;
  let res = hits.join('\n');
  if (hits.length >= MAX_HITS) res += `\n[ss-munch] truncated at ${MAX_HITS} hits`;
  else if (truncatedFiles) res += `\n[ss-munch] scanned first ${MAX_FILES} of ${supported.length} files`;
  return res;
}

async function dispatch(name, a) {
  if (name === 'munch_outline') return munchOutline(a.file);
  if (name === 'munch_symbol') return munchSymbol(a.file, a.name);
  if (name === 'munch_search') return munchSearch(a.name, a.path);
  throw new Error(`unknown tool: ${name}`);
}

const TOOLS = [
  { name: 'munch_outline', description: 'List the symbols in one file (functions, classes, methods, types) as compact rows "<startLine>-<endLine>  <kind>  <name><signature>" — read a file\'s shape without reading the file.', inputSchema: { type: 'object', properties: { file: { type: 'string', description: 'Path to the source file (language detected by extension)' } }, required: ['file'] } },
  { name: 'munch_symbol', description: 'Return the exact source of one symbol by name from a file (prefixed "# <file>:<start>-<end>") — read a single function/class instead of the whole file.', inputSchema: { type: 'object', properties: { file: { type: 'string', description: 'Path to the source file' }, name: { type: 'string', description: 'Symbol name to extract' } }, required: ['file', 'name'] } },
  { name: 'munch_search', description: 'Find symbols whose name contains <name> (case-insensitive) across git-tracked source files under <path> (default "."), as "<path>:<line>  <kind>  <name>". Bounded scan.', inputSchema: { type: 'object', properties: { name: { type: 'string', description: 'Substring to match against symbol names' }, path: { type: 'string', description: 'Directory to search (default ".")' } }, required: ['name'] } },
];

function send(obj) { process.stdout.write(JSON.stringify(obj) + '\n'); }

async function handle(line) {
  let msg;
  try { msg = JSON.parse(line); } catch { return; }
  const { id, method, params } = msg;
  if (method === 'initialize') {
    send({ jsonrpc: '2.0', id, result: { protocolVersion: params?.protocolVersion || '2025-06-18', capabilities: { tools: { listChanged: false } }, serverInfo: { name: 'ss-munch', version: '0.1.0' } } });
  } else if (method === 'ping') {
    send({ jsonrpc: '2.0', id, result: {} });
  } else if (typeof method === 'string' && method.startsWith('notifications/')) {
    // notifications get no response
  } else if (method === 'tools/list') {
    send({ jsonrpc: '2.0', id, result: { tools: TOOLS } });
  } else if (method === 'tools/call') {
    const nm = params?.name, ar = params?.arguments || {};
    try { send({ jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: await dispatch(nm, ar) }] } }); }
    catch (e) { send({ jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: 'error: ' + String(e?.message || e) }], isError: true } }); }
  } else if (id !== undefined && id !== null) {
    send({ jsonrpc: '2.0', id, error: { code: -32601, message: 'method not found: ' + method } });
  }
}

// Never crash: log to stderr (NOT stdout - that is the JSON-RPC channel) and keep running.
process.on('uncaughtException', (e) => { try { process.stderr.write('ss-munch: ' + String(e?.stack || e) + '\n'); } catch {} });
process.on('unhandledRejection', (e) => { try { process.stderr.write('ss-munch: ' + String(e) + '\n'); } catch {} });

// No explicit exit: when stdin closes the event loop drains and Node exits naturally.
// Do NOT call process.exit() — it aborts libuv mid-close while the WASM runtime has a
// pending async handle (UV_HANDLE_CLOSING) on Windows.
let buf = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  buf += chunk;
  let nl;
  while ((nl = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, nl); buf = buf.slice(nl + 1);
    if (line.trim()) handle(line).catch(() => {});   // a handler rejection must never crash the server
  }
});
```

- [ ] **Step 3: Run the smoke test to verify it passes**

Run:
```bash
cd "$(git rev-parse --show-toplevel)"
node --check mcp/munch/server.mjs && \
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"munch_outline","arguments":{"file":"tests/fixtures/munch/calc.js"}}}' \
  | node mcp/munch/server.mjs
```
Expected: three JSON lines — `id:1` with `serverInfo.name":"ss-munch"`; `id:2` with 3 tools; `id:3` whose `content[0].text` contains `function  alpha`, `class  Gamma`, and `method  doThing`. Process exits 0 (clean drain, no assertion).

- [ ] **Step 4: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add mcp/munch/server.mjs
git commit -m "feat(ss-munch): JSON-RPC stdio server with outline/symbol/search tools"
```

---

### Task 4: `tests/munch.test.sh` behavioral suite + wire `tests/run.sh` to [17/17]

The single committed test for ss-munch: protocol handshake + all 3 tools + error paths, driven over real stdio against `tests/fixtures/munch/`. Mirrors `tests/ctx-mcp.test.sh`.

**Files:**
- Create: `tests/munch.test.sh`
- Modify: `tests/run.sh` (relabel `[N/16]` → `[N/17]`; add a `[17/17]` block)

**Interfaces:**
- Consumes: `mcp/munch/server.mjs`, `mcp/munch/extract.mjs`, `tests/fixtures/munch/*`.

- [ ] **Step 1: Write the test (it fails because the file does not exist yet — write it, then run)**

Create `tests/munch.test.sh`:
```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Behavioral tests for the ss-munch MCP server (drives it via piped JSON-RPC over stdio).
# Paths passed to the server are repo-relative; the server runs with cwd=$ROOT so they
# resolve (Node existsSync cannot resolve Git-Bash /c/... absolutes on Windows).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
fail=0
chk() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; fail=1; fi; }

if ! command -v node >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "  SKIP munch (node/jq missing)"
else
  SRV="$ROOT/mcp/munch/server.mjs"
  node --check "$SRV" || fail=1
  node --check "$ROOT/mcp/munch/extract.mjs" || fail=1

  INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}'
  # drive(): feed INIT + the given JSON-RPC lines, capture all response lines (cwd=$ROOT)
  drive() { { printf '%s\n' "$INIT"; printf '%s\n' "$@"; } | timeout 60 node "$SRV" 2>/dev/null; }
  rid() { printf '%s\n' "$1" | jq -c "select(.id==$2)"; }
  txt() { rid "$1" "$2" | jq -r '.result.content[0].text'; }

  # --- protocol ---
  O="$(drive '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' '{"jsonrpc":"2.0","id":3,"method":"ping"}')"
  chk "init serverInfo ss-munch" '[ "$(rid "$O" 1 | jq -r ".result.serverInfo.name")" = "ss-munch" ] && [ "$(rid "$O" 1 | jq -r ".result.capabilities.tools|type")" = "object" ]'
  chk "init echoes protocol"     '[ "$(rid "$O" 1 | jq -r ".result.protocolVersion")" = "2025-06-18" ]'
  chk "tools/list = 3"           '[ "$(rid "$O" 2 | jq -r ".result.tools|length")" = "3" ]'
  chk "tool names"               '[ "$(rid "$O" 2 | jq -rc "[.result.tools[].name]|sort|join(\",\")")" = "munch_outline,munch_search,munch_symbol" ]'
  chk "ping empty result"        '[ "$(rid "$O" 3 | jq -c ".result")" = "{}" ]'

  # --- munch_outline (JS: function / arrow / class / method) ---
  A="$(drive '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"munch_outline","arguments":{"file":"tests/fixtures/munch/calc.js"}}}')"
  chk "outline js symbols" 'T="$(txt "$A" 4)"; printf "%s" "$T" | grep -q "function  alpha" && printf "%s" "$T" | grep -q "function  beta" && printf "%s" "$T" | grep -q "class  Gamma" && printf "%s" "$T" | grep -q "method  doThing"'

  # --- cross-language outline (Python, Go) ---
  P="$(drive '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"munch_outline","arguments":{"file":"tests/fixtures/munch/util.py"}}}' '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"munch_outline","arguments":{"file":"tests/fixtures/munch/main.go"}}}')"
  chk "outline python" 'printf "%s" "$(txt "$P" 5)" | grep -q "function  do_thing" && printf "%s" "$(txt "$P" 5)" | grep -q "class  Gamma"'
  chk "outline go"     'printf "%s" "$(txt "$P" 6)" | grep -q "function  Alpha" && printf "%s" "$(txt "$P" 6)" | grep -q "method  Area"'

  # --- munch_symbol exact body + prefix ---
  S="$(drive '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"munch_symbol","arguments":{"file":"tests/fixtures/munch/util.py","name":"do_thing"}}}')"
  chk "symbol prefix line" 'printf "%s" "$(txt "$S" 7)" | head -1 | grep -qE "^# tests/fixtures/munch/util.py:[0-9]+-[0-9]+$"'
  chk "symbol body"        'printf "%s" "$(txt "$S" 7)" | grep -qF "def do_thing(self):"'

  # --- munch_search across git-tracked fixtures (alpha is in calc.js + util.py + lib.rs) ---
  H="$(drive '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"munch_search","arguments":{"name":"alpha","path":"tests/fixtures/munch"}}}')"
  chk "search finds js"  'printf "%s" "$(txt "$H" 8)" | grep -qE "calc.js:[0-9]+  function  alpha"'
  chk "search finds py"  'printf "%s" "$(txt "$H" 8)" | grep -qE "util.py:[0-9]+  function  alpha"'

  # --- error paths ---
  E="$(drive '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"munch_outline","arguments":{"file":"tests/fixtures/munch/README.txt"}}}' '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"munch_symbol","arguments":{"file":"tests/fixtures/munch/calc.js","name":"nope"}}}')"
  chk "unsupported ext"   'printf "%s" "$(txt "$E" 9)" | grep -qF "unsupported file type"'
  chk "symbol not found"  'printf "%s" "$(txt "$E" 10)" | grep -qF "not found in" && printf "%s" "$(txt "$E" 10)" | grep -qF "munch_outline"'

  # --- unknown tool -> isError; unknown method -> -32601; notifications -> no output ---
  U="$(drive '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"nope","arguments":{}}}')"
  chk "unknown tool isError" '[ "$(rid "$U" 11 | jq -r ".result.isError")" = "true" ]'
  M="$(drive '{"jsonrpc":"2.0","id":12,"method":"bogus/method"}')"
  chk "unknown method -32601" '[ "$(rid "$M" 12 | jq -r ".error.code")" = "-32601" ]'
  N="$(drive '{"jsonrpc":"2.0","method":"notifications/initialized"}' '{"jsonrpc":"2.0","method":"notifications/whatever"}')"
  chk "notifications no output" '[ "$(printf "%s\n" "$N" | grep -c .)" -eq 1 ]'
fi

echo
[ "$fail" -eq 0 ] && echo "MUNCH TESTS PASS" || echo "MUNCH TESTS FAILED"
exit "$fail"
```

- [ ] **Step 2: Run the munch suite to verify it passes**

Run:
```bash
cd "$(git rev-parse --show-toplevel)"
bash tests/munch.test.sh
```
Expected: every line `PASS`, final `MUNCH TESTS PASS`, exit 0. (If `munch_search` finds 0 hits, the fixtures are not git-tracked yet — they were committed in Task 2; confirm with `git ls-files tests/fixtures/munch`.)

- [ ] **Step 3: Wire `tests/run.sh` — relabel to /17 and add the munch block**

In `tests/run.sh`, change every occurrence of `/16]` to `/17]` (16 labels: `[1/16]`…`[16/16]` → `[1/17]`…`[16/17]`), then insert a new block immediately before the final `echo` / summary line (after the `[16/17] ctx-mcp server` block):
```bash
echo "[17/17] munch-mcp server"
if bash "$ROOT/tests/munch.test.sh" >/dev/null 2>&1; then
  echo "      PASS"
else
  echo "      FAIL - munch-mcp suite"; fail=1
fi
```

- [ ] **Step 4: Run the full suite**

Run:
```bash
cd "$(git rev-parse --show-toplevel)"
bash tests/run.sh
```
Expected: `[1/17]`…`[17/17]` all PASS, final `ALL TESTS PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add tests/munch.test.sh tests/run.sh
git commit -m "test(ss-munch): behavioral MCP suite; wire run.sh to [17/17]"
```

---

### Task 5: Register the server + skill + cockpit detection

Make `ss-munch` visible to the harness (`.mcp.json`), document it as a skill, and have the Front-1 cockpit report code-exploration as native.

**Files:**
- Modify: `.mcp.json` (add the `ss-munch` server)
- Create: `skills/munch/SKILL.md`
- Modify: `scripts/ss-context:51` and `scripts/ss-context.ps1` (detect `"ss-munch"` in `.mcp.json`)

**Interfaces:**
- Consumes: `mcp/munch/server.mjs`.

- [ ] **Step 1: Add the server to `.mcp.json`**

Replace the contents of `.mcp.json` with:
```json
{
  "mcpServers": {
    "ss-ctx": {
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/mcp/server.mjs"]
    },
    "ss-munch": {
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/mcp/munch/server.mjs"]
    }
  }
}
```
Verify: `jq -e '.mcpServers["ss-munch"].args[0]' .mcp.json` prints the munch server path.

- [ ] **Step 2: Create `skills/munch/SKILL.md`**

```markdown
---
name: ss-munch
description: Use to read a single code symbol (a function/class/method by name) or a compact file outline instead of a whole file - the ss-munch MCP server parses a real AST (vendored tree-sitter) and returns exactly the symbol asked for, so exploring code costs tens of lines, not thousands. Front 3 of SuperStack's context all-rounder (the source-code sandbox).
---

# Munch - read the symbol, not the file

The default way to understand code is `Read` (whole file) + `Grep` (matching lines). For a large file you
only needed one function from, `Read` burns the whole file into context and `Grep` finds the line but not
the symbol's bounds. `ss-munch` returns **exactly the symbol asked for** (or a compact map of a file's
symbols), parsed from a real AST so the bounds are correct. Where [[ss-ctx]] keeps *runtime output* out of
context, `ss-munch` keeps *source code* out of context.

## Tools (MCP server, Front 3)

When the `ss-munch` MCP server is connected, prefer these over `Read`/`Grep` for code you want to explore
by symbol:

- `munch_outline(file)` - one row per symbol: `<startLine>-<endLine>  <kind>  <name><signature>`. Read a
  file's shape without reading the file.
- `munch_symbol(file, name)` - the exact source of one symbol, prefixed `# <file>:<start>-<end>`. Read a
  single function/class instead of the whole file. Not found -> a message + a hint to run `munch_outline`.
- `munch_search(name, path?)` - symbols whose name contains `name` (case-insensitive) across **git-tracked**
  source files under `path` (default `.`), as `<path>:<line>  <kind>  <name>`. Bounded scan (<=2000 files,
  <=200 hits); parses on demand (no index).

## Languages (v1)

JavaScript/JSX, TypeScript, TSX, Python, Go, Rust, Java - by file extension. Adding a language later is a
vendored grammar `.wasm` + a config row, not code.

## Note

- Read-only: it parses files and returns slices, runs no user code, writes nothing, and (only in
  `munch_search`) shells `git ls-files` to enumerate tracked files - so it won't wander into
  `node_modules`/build dirs or untracked secrets.
- Parsed source may contain secrets (same as `Read`); it stays in your context, not persisted.
- The grammars are tree-sitter 0.20-ABI; very new syntax may mis-parse but the stable node types we
  classify (functions/classes/methods/types) extract reliably.

## Lineage

Original to SuperStack - Front 3 of the context all-rounder, the **jcodemunch** (jgravelle) code-retrieval
capability rebuilt natively (inspiration-only). A second MCP server alongside [[ss-ctx]], kept separate so
`ss-ctx` stays dependency-free. The cockpit ([[ss-context]]) reports it as `code exploration: detected
(native)`. On-disk symbol index + call-graph/references are later enhancements.
```

- [ ] **Step 3: Update the cockpit detection (both twins)**

In `scripts/ss-context`, replace line 51 (the `cx_det` block) so it detects the registered server:
```bash
if grep -qs '"ss-munch"' .mcp.json 2>/dev/null; then cx_det="detected"; cx_hint="ss-munch (native)"; elif grep -qs 'jcodemunch' .mcp.json "$HOME/.claude.json" 2>/dev/null; then cx_det="detected"; cx_hint="jcodemunch (mcp)"; fi
```
In `scripts/ss-context.ps1`, find the matching `cx_det` block and make it detect `"ss-munch"` in `.mcp.json` (case-sensitive `Select-String -CaseSensitive -SimpleMatch '"ss-munch"'` to match the bash `grep` exactly — PowerShell's default match is case-insensitive; see the parity-gotchas note). Set `$cxDet="detected"; $cxHint="ss-munch (native)"` on a hit, keeping the existing `jcodemunch` elif as the fallback.

- [ ] **Step 4: Verify detection + skill lint**

Run:
```bash
cd "$(git rev-parse --show-toplevel)"
bash scripts/lint-skills.sh "$ROOT" >/dev/null && echo "LINT_OK"
bash scripts/ss-context | grep -i 'code exploration'
```
Expected: `LINT_OK`; the cockpit row reads `code exploration   detected   ss-munch (native)`.
If both twins are testable in this environment, also confirm the PowerShell cockpit:
`pwsh -File scripts/ss-context.ps1 | Select-String 'code exploration'` shows the same `ss-munch (native)`.

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git add .mcp.json skills/munch/SKILL.md scripts/ss-context scripts/ss-context.ps1
git commit -m "feat(ss-munch): register MCP server, add skill, cockpit detects native"
```

---

### Task 6: Surface in README + CHANGELOG

**Files:**
- Modify: `README.md` (skill count → 31; "2 MCP servers"; add ss-munch where ss-ctx is described)
- Modify: `CHANGELOG.md` (`[Unreleased]` entry)

**Interfaces:** none (docs only).

- [ ] **Step 1: Confirm the new skill count**

Run:
```bash
cd "$(git rev-parse --show-toplevel)"
ls -1 skills/*/SKILL.md | wc -l
```
Expected: `31` (was 30; Task 5 added `skills/munch/SKILL.md`). Use this number in the README edits.

- [ ] **Step 2: Update `README.md`**

- Update the skill-count references to **31 skills** and the MCP-server references to **2 MCP servers** (search the README for the current "30" / "1 MCP server" / "MCP server" phrasing and update each).
- Where `ss-ctx` is listed (the MCP-server / context all-rounder section), add a sibling line for `ss-munch`, e.g.:
  > **ss-munch** — symbol-level code retrieval: `munch_outline` / `munch_symbol` / `munch_search` read one symbol or a file outline instead of a whole file. A second, parser-vendored MCP server (tree-sitter WASM, zero-install), Front 3 of the context all-rounder.
- If the README has a "What's new" / roadmap section, move "symbol-level code retrieval (ss-munch)" from roadmap/next to shipped.

Verify:
```bash
grep -c 'ss-munch' README.md          # >= 1
grep -Eq '2 MCP servers' README.md && echo "SERVERS_OK"
grep -Eq '31 ' README.md && echo "COUNT_OK"
```
Expected: a positive ss-munch count, `SERVERS_OK`, `COUNT_OK`.

- [ ] **Step 3: Add a `CHANGELOG.md` entry**

Under `## [Unreleased]` (currently empty after v0.7.0), add:
```markdown
### Added
- **ss-munch** (Front 3) — symbol-level code retrieval: a second, parser-vendored MCP server
  (`munch_outline`, `munch_symbol`, `munch_search`) that returns one code symbol or a compact file
  outline instead of a whole file, parsed from a real tree-sitter AST (vendored web-tree-sitter 0.20.8 +
  Core 7 grammars, zero-install). Read-only. The `/ss-context` cockpit now reports
  `code exploration: detected (native)`.
```

Verify: `grep -A2 'Unreleased' CHANGELOG.md | grep -q 'ss-munch' && echo "CHANGELOG_OK"`.

- [ ] **Step 4: Final full-suite run + commit**

```bash
cd "$(git rev-parse --show-toplevel)"
bash tests/run.sh | tail -1     # expect: ALL TESTS PASS
git add README.md CHANGELOG.md
git commit -m "docs(ss-munch): surface in README (31 skills, 2 MCP servers) + CHANGELOG"
```

---

## Notes for the implementer

- **Why everything is already proven:** the plan-stage pre-verification vendored the files, built `extract.mjs`, and drove a prototype server end-to-end on Windows — confirming zero-install load, all 7 languages, byte-offset slicing, the teardown rule, and the full JSON-RPC handshake. The code blocks above are that proven implementation. Your job is to land it task-by-task with the committed tests as the gate.
- **The two non-obvious rules (do not "simplify" them away):** (1) cache one Parser per language; (2) never `process.exit()` after WASM work — rely on natural drain. Both are load-bearing on Windows.
- **No `process.exit()` in any Node you write here** (server or harness) — use `process.exitCode`.
- This is one cross-platform Node process: **no PowerShell twin** for the server (the only `.ps1` touched is the cockpit detection in Task 5).

## Self-Review

**Spec coverage:** approach (second vendored server) → Tasks 1+3+5; proven mechanism / ABI pairing → Task 1 + Global Constraints; Core 7 + ext map → Task 2 (Global Constraints); 3 tools w/ formats + per-language node types → Tasks 2–3; lazy grammar load + parser cache → Task 2; registration `.mcp.json` → Task 5; `skills/munch/SKILL.md` → Task 5; cockpit detection → Task 5; `tests/munch.test.sh` + fixtures + `run.sh [17/17]` → Tasks 2+4; README/CHANGELOG (31 skills, 2 MCP servers) → Task 6; security/read-only + git-tracked bound → Tasks 3+5 (Global Constraints). Out-of-scope items (on-disk index, file-watching, call-graph, >Core-7, 0.25 grammars, PS twin) are intentionally excluded. No gaps.

**Placeholder scan:** every code step contains complete content (full `extract.mjs`, full `server.mjs`, full `munch.test.sh`, full `SKILL.md`, exact `.mcp.json`, exact cockpit lines). No TBD/TODO/"handle errors"/"similar to". README edits are the one search-and-update step (the exact current phrasings vary), with verifiable greps as the gate.

**Type consistency:** `extractOutline`/`findSymbols` return `{kind,name,signature,startLine,endLine,startIndex,endIndex}` consistently across Tasks 2–4; `server.mjs`'s `fmtRow` and `munchSymbol`/`munchSearch` consume exactly those fields; `EXT_TO_LANG`/`detectLang` signatures match between `extract.mjs` and `server.mjs`. Tool names `munch_outline`/`munch_symbol`/`munch_search` are identical in `server.mjs` `TOOLS`, `dispatch`, and the test's `tool names` assertion.
