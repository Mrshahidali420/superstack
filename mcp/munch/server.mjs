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
