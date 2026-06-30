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
