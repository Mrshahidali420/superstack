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
