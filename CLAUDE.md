# dadbod-grip.nvim

Neovim 0.10+ Lua plugin for editable database grids. It talks to PostgreSQL,
MySQL/MariaDB, SQLite, DuckDB/MotherDuck, and files through external CLIs.

## Layout

- `plugin/dadbod-grip.lua`: loader and Neovim version guard.
- `lua/dadbod-grip/init.lua`: setup, commands, sessions, file-as-table routing.
- `lua/dadbod-grip/view.lua`: grid rendering, highlights, grid actions.
- `lua/dadbod-grip/schema.lua`: schema sidebar, metadata, DDL entry points.
- `lua/dadbod-grip/query_pad.lua`: SQL scratch pad and notebook execution.
- `lua/dadbod-grip/data.lua`: pure immutable staged-edit state.
- `lua/dadbod-grip/query.lua`: pure query specs.
- `lua/dadbod-grip/sql.lua`: SQL generation and quoting helpers.
- `lua/dadbod-grip/db.lua`: I/O facade; returns `(result, err)`.
- `lua/dadbod-grip/adapters/*.lua`: CLI-backed DB adapters.
- `tests/spec/*_spec.lua`: custom headless Neovim specs.
- Docs: `doc/dadbod-grip.txt`, `README.md`, `KEYMAPS.md`.

## Commands

- `just test`: all specs.
- `just spec data`: one spec, e.g. `tests/spec/data_spec.lua`.
- `just lint`: `luacheck lua/ --no-unused-args --no-max-line-length`.
- `just dev`: open Neovim with this repo on `runtimepath`.
- `just start`: run the demo with `:GripStart`.
- `just seed-sqlite`, `just seed-duckdb`, `just seed-pg`, `just seed-mysql`.

Underlying test command:

```bash
nvim --headless -u tests/minimal_init.lua -l tests/run_specs.lua
```

## Architecture Rules

- Keep `data.lua`, `query.lua`, and `sql.lua` free of UI, shell, FS, and DB I/O.
- Keep shell/database I/O in `db.lua` and adapter modules.
- `data.lua` state is immutable. Copy mutable subtrees; share rows/columns only
  as immutable values.
- Adapter-facing functions should return `(result, err)` instead of throwing.
- Put backend-specific behavior behind adapter methods, not scattered through
  UI/query modules.
- Preserve transaction safety for mutations: preview/confirm where expected,
  apply in a transaction, rollback on error.

## Conventions

- Lua style: `local M = {}`, local requires, plain tables, two-space indent.
- Prefer `vim.api` and structured Neovim APIs over command-string tricks.
- Use existing SQL quoting/helpers; never concatenate unescaped identifiers or
  user values.
- NULLs: CLI output often maps DB NULL to `""`; staged NULL uses
  `data.NULL_SENTINEL`.
- Reuse existing UI/keymap/picker helpers before adding new plumbing.
- Avoid new dependencies unless the user explicitly accepts the tradeoff.
- Update docs when commands, keymaps, setup options, or public behavior change.
- Bump `lua/dadbod-grip/version.lua` once per release commit, not once per
  individual fix while iterating in the same commit.

## Testing

- Run the narrowest spec while iterating; run `just test` before finishing.
- Pure modules get direct unit specs using existing local test helpers.
- Adapter tests should mock `vim.system`/executables where possible.
- UI/session changes should use headless Neovim tests that inspect buffers,
  windows, highlights, extmarks, or module state.
- For adapter SQL, write coverage for affected backends or isolate the behavior
  clearly.

## Risk Areas

- SQL parsing is lightweight. Test CTEs, comments, quoted identifiers, and mixed
  case when touching it.
- Grid layout depends on display width/truncation. Check narrow windows and long
  values for render changes.
- Autocmd groups should stay `clear = true` to avoid duplicate handlers on
  reload.
- DuckDB file-as-table, federation, remote URLs, watch/write mode, and write-back
  share paths but have different persistence and destructive-write semantics.

## Agent Defaults

- For reversible local edits, make the smallest coherent change and verify it.
- Pause before public API changes, new dependencies, destructive data behavior,
  provider/auth changes, or broad rewrites.
- Do not overwrite unrelated dirty-tree work.
- `AGENTS.md` should remain a symlink to this file.
