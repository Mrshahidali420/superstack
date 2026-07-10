<!-- superstack:context-routing -->
## Context routing (SuperStack)

Keep raw bulk out of the context window; retrieve on demand:

- **Explore code by symbol, not by file.** Prefer `munch_outline` (file shape) and
  `munch_symbol` (one function/class) over `Read`; `munch_search` over `Grep` for
  symbol names. `Read` stays correct for files you are about to Edit.
- **Run verbose commands in the sandbox.** Prefer `ctx_execute` / `ctx_batch_execute`
  over Bash when output may exceed ~20 lines (builds, suites, logs); retrieve detail
  later via `ctx_search` / `ctx_show`. Bash stays right for git and short commands.
- **Fetch pages via `ctx_fetch_and_index` + `ctx_search`** - never raw HTML into context.

If a tool is not connected, fall back to the defaults - never block.
<!-- /superstack:context-routing -->
