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
