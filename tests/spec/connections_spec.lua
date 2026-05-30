-- connections_spec.lua: tests for connection picker helpers.

local connections = require("dadbod-grip.connections")
local grip_picker = require("dadbod-grip.grip_picker")
local grip = require("dadbod-grip")

local pass = 0
local fail = 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    pass = pass + 1
  else
    fail = fail + 1
    print("FAIL: " .. name .. ": " .. tostring(err))
  end
end

local function eq(a, b, msg)
  assert(a == b, (msg or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
end

local function with_cwd(dir, fn)
  local prev = vim.fn.getcwd()
  vim.fn.mkdir(dir, "p")
  vim.cmd("cd " .. vim.fn.fnameescape(dir))
  local ok, err = pcall(fn)
  vim.cmd("cd " .. vim.fn.fnameescape(prev))
  if not ok then error(err) end
end

local function with_home(dir, fn)
  local prev = vim.env.HOME
  vim.env.HOME = dir
  local ok, err = pcall(fn)
  vim.env.HOME = prev
  if not ok then error(err) end
end

test("scan_local_sqlite_files returns sqlite connection items", function()
  local dir = vim.fn.tempname()
  with_cwd(dir, function()
    local cwd = vim.fn.getcwd()
    vim.fn.writefile({}, dir .. "/app.db")
    vim.fn.mkdir(dir .. "/data", "p")
    vim.fn.writefile({}, dir .. "/data/archive.sqlite3")

    local items = connections._scan_local_sqlite_files()
    eq(#items, 2, "sqlite file count")
    eq(items[1].name, "app.db", "root display name")
    eq(items[1].connection_name, "app", "root connection name")
    eq(items[1].url, "sqlite:" .. cwd .. "/app.db", "root sqlite URL")
    eq(items[1]._local_sqlite, true, "root marker")
    eq(items[2].name, "data/archive.sqlite3", "nested display name")
    eq(items[2].connection_name, "archive", "nested connection name")
    eq(items[2].url, "sqlite:" .. cwd .. "/data/archive.sqlite3", "nested sqlite URL")
  end)
end)

test("scan_local_duckdb_files returns duckdb connection items", function()
  local dir = vim.fn.tempname()
  with_cwd(dir, function()
    local cwd = vim.fn.getcwd()
    vim.fn.writefile({}, dir .. "/analytics.duckdb")
    vim.fn.mkdir(dir .. "/warehouse", "p")
    vim.fn.writefile({}, dir .. "/warehouse/mart.duckdb")

    local items = connections._scan_local_duckdb_files()
    eq(#items, 2, "duckdb file count")
    eq(items[1].name, "analytics.duckdb", "root display name")
    eq(items[1].connection_name, "analytics", "root connection name")
    eq(items[1].url, "duckdb:" .. cwd .. "/analytics.duckdb", "root duckdb URL")
    eq(items[1]._local_duckdb, true, "root marker")
    eq(items[2].name, "warehouse/mart.duckdb", "nested display name")
    eq(items[2].connection_name, "mart", "nested connection name")
    eq(items[2].url, "duckdb:" .. cwd .. "/warehouse/mart.duckdb", "nested duckdb URL")
  end)
end)

test("pick switches local sqlite file as saved connection", function()
  local dir = vim.fn.tempname()
  with_cwd(dir, function()
    local cwd = vim.fn.getcwd()
    vim.fn.writefile({}, dir .. "/app.db")

    local orig_open = grip_picker.open
    local orig_switch = connections.switch
    local orig_gdb = vim.g.db
    local captured_opts
    local switched
    grip_picker.open = function(opts)
      captured_opts = opts
    end
    connections.switch = function(url, name, conn_type, opts)
      switched = { url = url, name = name, conn_type = conn_type, opts = opts }
    end
    vim.g.db = "sqlite:dummy.db"

    local ok, err = pcall(function()
      connections.pick({ on_cancel = function() end })
      assert(captured_opts, "picker should open")
      local sqlite_item
      for _, item in ipairs(captured_opts.items) do
        if item._local_sqlite then
          sqlite_item = item
          break
        end
      end
      assert(sqlite_item, "local sqlite item should be present")
      captured_opts.on_select(sqlite_item)
    end)

    grip_picker.open = orig_open
    connections.switch = orig_switch
    vim.g.db = orig_gdb
    if not ok then error(err) end

    eq(switched.url, "sqlite:" .. cwd .. "/app.db", "switch URL")
    eq(switched.name, "app", "switch name")
    eq(switched.conn_type, nil, "sqlite is a DB connection, not file-as-table")
  end)
end)

test("pick switches local duckdb file as saved connection", function()
  local dir = vim.fn.tempname()
  with_cwd(dir, function()
    local cwd = vim.fn.getcwd()
    vim.fn.writefile({}, dir .. "/analytics.duckdb")

    local orig_open = grip_picker.open
    local orig_switch = connections.switch
    local orig_gdb = vim.g.db
    local captured_opts
    local switched
    grip_picker.open = function(opts)
      captured_opts = opts
    end
    connections.switch = function(url, name, conn_type, opts)
      switched = { url = url, name = name, conn_type = conn_type, opts = opts }
    end
    vim.g.db = "sqlite:dummy.db"

    local ok, err = pcall(function()
      connections.pick({ on_cancel = function() end })
      assert(captured_opts, "picker should open")
      local duckdb_item
      for _, item in ipairs(captured_opts.items) do
        if item._local_duckdb then
          duckdb_item = item
          break
        end
      end
      assert(duckdb_item, "local duckdb item should be present")
      captured_opts.on_select(duckdb_item)
    end)

    grip_picker.open = orig_open
    connections.switch = orig_switch
    vim.g.db = orig_gdb
    if not ok then error(err) end

    eq(switched.url, "duckdb:" .. cwd .. "/analytics.duckdb", "switch URL")
    eq(switched.name, "analytics", "switch name")
    eq(switched.conn_type, nil, "duckdb is a DB connection, not file-as-table")
  end)
end)

test("pick display caps long connection names so URL remains visible", function()
  local orig_open = grip_picker.open
  local orig_list = connections.list
  local captured_opts
  grip_picker.open = function(opts)
    captured_opts = opts
  end
  connections.list = function()
    return {
      {
        name = "DuckDB (memory)  · read files; no cross-query state",
        url = "duckdb::memory:",
        source = "file",
      },
    }
  end

  local ok, err = pcall(function()
    connections.pick({ on_cancel = function() end })
    assert(captured_opts, "picker should open")
    local line = captured_opts.display(captured_opts.items[1])
    assert(line:find("…", 1, true), "long name should be truncated: " .. line)
    assert(not line:find("cross%-query", 1, false), "name column should stay compact: " .. line)
    assert(line:find("duckdb::memory:", 1, true), "URL should remain visible: " .. line)
  end)

  grip_picker.open = orig_open
  connections.list = orig_list
  if not ok then error(err) end
end)

test("pick full display shows duckdb path from the left", function()
  local orig_open = grip_picker.open
  local orig_list = connections.list
  local captured_opts
  grip_picker.open = function(opts)
    captured_opts = opts
  end
  connections.list = function()
    return {
      {
        name = "DuckDB (scratch) · /tmp/grip_scratch.duckdb",
        url = "duckdb:/tmp/grip_scratch.duckdb",
        source = "file",
      },
    }
  end

  local ok, err = pcall(function()
    connections.pick({ on_cancel = function() end })
    assert(captured_opts, "picker should open")
    local item = captured_opts.items[1]
    for _, action in ipairs(captured_opts.actions) do
      local key = action.key
      if key == "M" then
        action.fn(item)
      end
    end
    local line = captured_opts.display(item)
    assert(line:find("duckdb:/tmp/grip", 1, true), "full display should show path prefix: " .. line)
  end)

  grip_picker.open = orig_open
  connections.list = orig_list
  if not ok then error(err) end
end)

test("remove deletes global connections from global file", function()
  local home = vim.fn.tempname()
  with_home(home, function()
    grip.setup({})
    local path = home .. "/.grip/connections.json"
    vim.fn.mkdir(home .. "/.grip", "p")
    vim.fn.writefile({ vim.fn.json_encode({
      { name = "temp1", url = "sqlite:temp1.db" },
      { name = "keep", url = "sqlite:keep.db" },
    }) }, path)

    connections.remove("temp1", "global", "sqlite:temp1.db")

    local data = vim.fn.json_decode(table.concat(vim.fn.readfile(path), "\n"))
    eq(#data, 1, "global connection count")
    eq(data[1].name, "keep", "remaining global connection")
  end)
end)

test("pick D removes global connection from global file", function()
  local home = vim.fn.tempname()
  with_home(home, function()
    grip.setup({})
    local path = home .. "/.grip/connections.json"
    vim.fn.mkdir(home .. "/.grip", "p")
    vim.fn.writefile({ vim.fn.json_encode({
      { name = "global_only", url = "sqlite:global-only.db" },
    }) }, path)

    local orig_open = grip_picker.open
    local orig_input = vim.fn.input
    local captured_opts
    grip_picker.open = function(opts)
      captured_opts = opts
    end
    vim.fn.input = function()
      return "y"
    end

    local ok, err = pcall(function()
      connections.pick({ on_cancel = function() end })
      assert(captured_opts, "picker should open")
      local item
      for _, c in ipairs(captured_opts.items) do
        if c.url == "sqlite:global-only.db" then
          item = c
          break
        end
      end
      assert(item and item.source == "global", "global item should be present")
      captured_opts.on_delete(item, function() end)
    end)

    grip_picker.open = orig_open
    vim.fn.input = orig_input
    if not ok then error(err) end

    local data = vim.fn.json_decode(table.concat(vim.fn.readfile(path), "\n"))
    eq(#data, 0, "global file should be empty")
  end)
end)

test("short_url keeps database schemes visible", function()
  eq(connections._short_url("sqlite:temp1.db"), "sqlite:temp1.db", "sqlite scheme")
  eq(connections._short_url("duckdb:analytics.duckdb"), "duckdb:analytics.duckdb", "duckdb scheme")
end)

test("short_url keeps the right side of database paths", function()
  local dir = vim.fn.tempname()
  with_cwd(dir, function()
    vim.fn.writefile({}, dir .. "/app.db")
    vim.fn.mkdir(dir .. "/data", "p")
    vim.fn.writefile({}, dir .. "/data/archive.sqlite3")

    local root = connections._short_url("sqlite:" .. vim.fn.getcwd() .. "/app.db")
    local nested = connections._short_url("sqlite:" .. vim.fn.getcwd() .. "/data/archive.sqlite3")
    assert(root:find("app%.db$", 1, false), "root sqlite filename should be visible: " .. root)
    assert(nested:find("archive%.sqlite3$", 1, false), "nested sqlite filename should be visible: " .. nested)
  end)
end)

test("short_url truncates long database paths from the left", function()
  local out = connections._short_url("duckdb:/Users/example/projects/acme/data/warehouse/analytics.duckdb")
  assert(out:find("^duckdb:…", 1, false), "short URL should use left ellipsis: " .. out)
  assert(out:find("analytics%.duckdb$", 1, false), "short URL should keep filename: " .. out)
end)

print(string.format("connections_spec: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
