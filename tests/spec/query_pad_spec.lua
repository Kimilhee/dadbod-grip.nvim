-- query_pad_spec.lua: unit tests for query_pad.sync_query
-- Tests the replace-vs-append logic without any DB I/O.
dofile("tests/minimal_init.lua")

local qp = require("dadbod-grip.query_pad")

local pass, fail = 0, 0

local function eq(a, b, msg)
  if a == b then
    pass = pass + 1
  else
    fail = fail + 1
    print(string.format("FAIL: %s\n  expected: %s\n  got:      %s", msg, tostring(b), tostring(a)))
  end
end

-- Helper: create a scratch buffer, wire it as the pad, return bufnr.
-- We expose _set_pad_bufnr for testing only.
local function make_pad()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].modifiable = true
  qp._set_pad_bufnr(bufnr)
  return bufnr
end

local function get_lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

local function set_lines(bufnr, lines)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

-- ── sync_query: populate empty pad ──────────────────────────────────────────

do
  local b = make_pad()
  set_lines(b, {})
  qp.sync_query("SELECT * FROM users")
  local lines = get_lines(b)
  eq(lines[1], "SELECT * FROM users", "empty pad: line 1 is the SQL")
  eq(#lines, 1, "empty pad: exactly 1 line")
end

-- ── sync_query: replace hint-only pad ───────────────────────────────────────

do
  local b = make_pad()
  set_lines(b, { "-- C-CR:run  gA:ai  go:tables", "" })
  qp.sync_query("SELECT * FROM orders")
  local lines = get_lines(b)
  eq(lines[1], "SELECT * FROM orders", "hint pad: line 1 is the SQL")
  eq(#lines, 1, "hint pad: exactly 1 line after replace")
end

-- ── sync_query: append to pad with existing content ─────────────────────────

do
  local b = make_pad()
  set_lines(b, { "SELECT id FROM users" })
  qp.sync_query("SELECT * FROM orders")
  local lines = get_lines(b)
  eq(lines[1], "SELECT id FROM users", "append: original query preserved on line 1")
  -- blank separator + appended SQL
  eq(lines[2], "", "append: blank separator line 2")
  eq(lines[3], "SELECT * FROM orders", "append: new SQL on line 3")
end

-- ── sync_query: multiple appends accumulate ──────────────────────────────────

do
  local b = make_pad()
  set_lines(b, { "SELECT 1" })
  qp.sync_query("SELECT 2")
  qp.sync_query("SELECT 3")
  local lines = get_lines(b)
  eq(lines[1], "SELECT 1", "multi-append: original preserved")
  eq(lines[3], "SELECT 2", "multi-append: second query appended")
  eq(lines[5], "SELECT 3", "multi-append: third query appended")
end

-- ── sync_query: hint on line 1, real content below → append, not replace ─────
-- The pad starts with the hint comment. If the user has written SQL below it,
-- the buffer is NOT empty. sync_query must append, not clobber.

do
  local b = make_pad()
  set_lines(b, {
    "-- C-CR:run  gA:ai  go:tables",
    "",
    "SELECT id, name FROM customers",
    "WHERE active = true",
  })
  qp.sync_query("SELECT * FROM orders")
  local lines = get_lines(b)
  eq(lines[1], "-- C-CR:run  gA:ai  go:tables", "hint+content: hint line preserved")
  eq(lines[3], "SELECT id, name FROM customers", "hint+content: user query preserved")
  local last = lines[#lines]
  eq(last, "SELECT * FROM orders", "hint+content: new query appended at end")
end

-- ── sync_query: no-op on blank/whitespace sql ────────────────────────────────

do
  local b = make_pad()
  set_lines(b, { "SELECT 1" })
  qp.sync_query("   ")
  local lines = get_lines(b)
  eq(#lines, 1, "whitespace sql: pad unchanged")
  eq(lines[1], "SELECT 1", "whitespace sql: content preserved")
end

-- ── sync_query: no-op when pad bufnr is nil ──────────────────────────────────

do
  qp._set_pad_bufnr(nil)
  local ok = pcall(qp.sync_query, "SELECT 1")
  eq(ok, true, "nil pad bufnr: no error thrown")
end

-- ── _has_real_content: pure helper tests ─────────────────────────────────────

do
  -- empty table
  eq(qp._has_real_content({}), false, "hrc: empty lines = no content")
  -- single blank line
  eq(qp._has_real_content({ "" }), false, "hrc: single blank = no content")
  -- whitespace only
  eq(qp._has_real_content({ "   " }), false, "hrc: whitespace only = no content")
  -- hint-only (single)
  eq(qp._has_real_content({ "-- C-CR:run  gA:ai  go:tables" }), false, "hrc: hint line only = no content")
  -- hint + blank line
  eq(qp._has_real_content({ "-- C-CR:run  gA:ai  go:tables", "" }), false, "hrc: hint+blank = no content")
  -- AI separator only
  eq(qp._has_real_content({ "-- AI generated: SELECT 1" }), false, "hrc: ai-sep only = no content")
  -- hint + real SQL
  eq(qp._has_real_content({ "-- C-CR:run  gA:ai  go:tables", "", "SELECT 1" }), true, "hrc: hint+sql = has content")
  -- real SQL (no hint)
  eq(qp._has_real_content({ "SELECT id FROM users" }), true, "hrc: plain sql = has content")
  -- multi-line SQL
  eq(qp._has_real_content({ "SELECT *", "FROM orders", "WHERE id = 1" }), true, "hrc: multiline sql = has content")
  -- AI sep + real SQL below
  eq(qp._has_real_content({ "-- AI generated:", "", "SELECT 42" }), true, "hrc: ai-sep+sql = has content")
end

-- ── _block_under_cursor ───────────────────────────────────────────────────────

-- Helper: create a buffer with lines, open it in a window, position cursor.
-- Returns bufnr. The window is set as current so nvim_win_get_cursor(0) works.
local function buf_with_cursor(lines, cursor_line)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  local win = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor", width = 80, height = 20, row = 0, col = 0, style = "minimal",
  })
  vim.api.nvim_win_set_cursor(win, { cursor_line, 0 })
  return bufnr, win
end

local function close_win(win)
  if vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
end

do
  -- cursor inside a ```sql block
  local lines = {
    "# Header",
    "Some text.",
    "```sql",
    "SELECT 1",
    "FROM dual",
    "```",
    "More text.",
  }
  local b, w = buf_with_cursor(lines, 4)
  local result = qp._block_under_cursor(b)
  eq(result, "SELECT 1\nFROM dual", "block_under_cursor: cursor inside block returns SQL")
  close_win(w)
end

do
  -- cursor on the opening fence line: still extracts the block below it
  local lines = { "```sql", "SELECT 2", "```" }
  local b, w = buf_with_cursor(lines, 1)
  local result = qp._block_under_cursor(b)
  eq(result, "SELECT 2", "block_under_cursor: cursor on opening fence extracts block below")
  close_win(w)
end

do
  -- cursor outside any block (plain text)
  local lines = { "Some prose.", "No SQL here." }
  local b, w = buf_with_cursor(lines, 1)
  local result = qp._block_under_cursor(b)
  eq(result, nil, "block_under_cursor: cursor outside block returns nil")
  close_win(w)
end

do
  -- cursor on the closing fence
  local lines = { "```sql", "SELECT 3", "```" }
  local b, w = buf_with_cursor(lines, 3)
  local result = qp._block_under_cursor(b)
  eq(result, nil, "block_under_cursor: cursor on closing fence returns nil")
  close_win(w)
end

do
  -- multiple blocks: cursor in second block returns only second block
  local lines = {
    "```sql",
    "SELECT 1",
    "```",
    "Text between blocks.",
    "```sql",
    "SELECT 2",
    "FROM t",
    "```",
  }
  local b, w = buf_with_cursor(lines, 6)
  local result = qp._block_under_cursor(b)
  eq(result, "SELECT 2\nFROM t", "block_under_cursor: cursor in second block returns second block")
  close_win(w)
end

do
  -- non-sql fence (```python) does not match
  local lines = { "```python", "print('hi')", "```" }
  local b, w = buf_with_cursor(lines, 2)
  local result = qp._block_under_cursor(b)
  eq(result, nil, "block_under_cursor: non-sql fence returns nil")
  close_win(w)
end

do
  -- unclosed block (no closing fence) returns nil
  local lines = { "```sql", "SELECT 4" }
  local b, w = buf_with_cursor(lines, 2)
  local result = qp._block_under_cursor(b)
  eq(result, nil, "block_under_cursor: unclosed block returns nil")
  close_win(w)
end

-- ── _statement_under_cursor ──────────────────────────────────────────────────

do
  local lines = {
    "-- inspect users",
    "SELECT * FROM users;",
    "",
    "-- remove old orders",
    "DELETE FROM orders WHERE created_at < '2024-01-01';",
    "",
    "CREATE TABLE audit_log (id integer);",
  }
  eq(qp._statement_under_cursor(lines, 1), "SELECT * FROM users", "statement_under_cursor: ignores leading SELECT comment")
  eq(qp._statement_under_cursor(lines, 4), "DELETE FROM orders WHERE created_at < '2024-01-01'", "statement_under_cursor: ignores leading DELETE comment")
  eq(qp._statement_under_cursor(lines, 7), "CREATE TABLE audit_log (id integer)", "statement_under_cursor: CREATE statement")
end

do
  local lines = {
    "-- SELECT * FROM employee2",
    "-- 주석 추가.",
    "",
    "delete FROM employee where id = 1;",
  }
  eq(qp._statement_under_cursor(lines, 4), "delete FROM employee where id = 1", "statement_under_cursor: DELETE after Korean comment")
end

do
  local lines = {
    "SELECT ';' AS semi;",
    "DELETE FROM logs WHERE message = 'not;split';",
  }
  eq(qp._statement_under_cursor(lines, 1), "SELECT ';' AS semi", "statement_under_cursor: ignores semicolon in string")
  eq(qp._statement_under_cursor(lines, 2), "DELETE FROM logs WHERE message = 'not;split'", "statement_under_cursor: next statement after string semicolon")
end

do
  local lines = {
    "SELECT 1; -- comment ; does not split",
    "UPDATE users SET name = 'A' WHERE id = 1;",
  }
  eq(qp._statement_under_cursor(lines, 2), "UPDATE users SET name = 'A' WHERE id = 1", "statement_under_cursor: ignores semicolon in line comment")
end

do
  local lines = {
    "-- C-CR:run block or buffer",
    "",
    "-- comment only;",
  }
  eq(qp._statement_under_cursor(lines, 3), nil, "statement_under_cursor: comment-only statement is empty")
end

-- ── _visual_line_range ───────────────────────────────────────────────────────

do
  local b, w = buf_with_cursor({ "SELECT 1;", "SELECT 2;", "SELECT 3;" }, 1)
  vim.cmd("normal! Vj")
  local start_line, end_line = qp._visual_line_range()
  eq(start_line, 1, "visual_line_range: forward selection start")
  eq(end_line, 2, "visual_line_range: forward selection end")
  vim.cmd("normal! \027")
  close_win(w)
  pcall(vim.api.nvim_buf_delete, b, { force = true })
end

do
  local b, w = buf_with_cursor({ "SELECT 1;", "SELECT 2;", "SELECT 3;" }, 3)
  vim.cmd("normal! Vk")
  local start_line, end_line = qp._visual_line_range()
  eq(start_line, 2, "visual_line_range: backward selection start")
  eq(end_line, 3, "visual_line_range: backward selection end")
  vim.cmd("normal! \027")
  close_win(w)
  pcall(vim.api.nvim_buf_delete, b, { force = true })
end

do
  local line = "insert into employee SELECT * FROM emp2 where id = 1;"
  local b, w = buf_with_cursor({ line }, 1)
  local start_col = line:find("SELECT", 1, true)
  vim.api.nvim_win_set_cursor(w, { 1, start_col - 1 })
  vim.cmd("normal! v$")
  eq(qp._visual_selection_text(b), "SELECT * FROM emp2 where id = 1;", "visual_selection_text: charwise selection is exact")
  vim.cmd("normal! \027")
  close_win(w)
  pcall(vim.api.nvim_buf_delete, b, { force = true })
end

do
  local b, w = buf_with_cursor({ "SELECT 1;", "SELECT 2;", "SELECT 3;" }, 2)
  vim.cmd("normal! V")
  eq(qp._visual_selection_text(b), "SELECT 2;", "visual_selection_text: linewise selection keeps whole selected line")
  vim.cmd("normal! \027")
  close_win(w)
  pcall(vim.api.nvim_buf_delete, b, { force = true })
end

do
  local grip = require("dadbod-grip")
  grip.setup({ completion = false })

  local orig_open = grip.open
  local captured_sql = nil
  grip.open = function(sql)
    captured_sql = sql
  end

  qp.open("sqlite:test.db")
  local bufnr = qp.get_pad_bufnr()
  set_lines(bufnr, { "SELECT 1;", "SELECT 2;", "SELECT 3;" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.cmd("normal! V")

  local callback = nil
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "v")) do
    if map.desc == "Grip: run selection" then
      callback = map.callback
      break
    end
  end
  assert(callback, "visual qpad_execute keymap should exist")
  callback()

  eq(captured_sql, "SELECT 2;", "visual qpad_execute: runs selected line only")
  grip.open = orig_open
  qp._set_pad_bufnr(nil)
end

print(string.format("\nquery_pad_spec: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
