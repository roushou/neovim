--- Packo dashboard: the read-only plugin window.
---
--- Owns the float, the row rendering, the on-demand detail view, and the
--- hand-off to |vim.pack.update()|. It never writes to the lockfile or the
--- plugin directory itself.

local config = require("packo.config")
local float = require("packo.float")
local pack = require("packo.pack")

local M = {}

local unpack = table.unpack or unpack

local ns = vim.api.nvim_create_namespace("packo")

-- open float state
local state = nil -- { win, buf, rows, detail }

local STATE_ORDER = { active = 0, inactive = 1, drift = 2, missing = 3, error = 4 }

local function opts()
	return config.options
end

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "packo" })
end

--- Coalesce calls that arrive close together (the async git checks).
local function debounce(ms, fn)
	local timer = vim.uv.new_timer()
	return function(...)
		local args = { ... }
		timer:stop()
		timer:start(
			ms,
			0,
			vim.schedule_wrap(function()
				fn(unpack(args))
			end)
		)
	end
end

local schedule_render = debounce(60, function()
	if float.is_open(state) then
		M.render()
	end
end)

--- Normalize a keymap option (string | string[] | false) to a list.
local function keys(spec)
	if spec == false or spec == nil then
		return {}
	end
	return type(spec) == "table" and spec or { spec }
end

local function short_path(p, maxlen)
	if not p or p == "" then
		return ""
	end
	local s = vim.fn.fnamemodify(p, ":~")
	if #s <= maxlen then
		return s
	end
	return s:sub(1, maxlen - 1) .. "…"
end

local function version_str(row)
	if row.version == nil then
		return ""
	end
	return tostring(row.version)
end

local function plug_dir()
	return vim.fs.joinpath(vim.fn.stdpath("data"), "site", "pack", "core", "opt")
end

--- A short comma list of at most `max` items (newest first for tags).
local function list(items, max)
	if #items == 0 then
		return "—"
	end
	if #items <= max then
		return table.concat(items, ", ")
	end
	return table.concat(items, ", ", 1, max) .. "…"
end

local function hl_range(buf, row, from, to, group)
	vim.api.nvim_buf_set_extmark(buf, ns, row, from, { end_col = to, hl_group = group })
end

--- Resolve a row's state and detail string from the raw `pack.list()` row.
local function evaluate(row)
	if row.missing then
		return "missing", "not on disk (restart to install)"
	end
	if row.health == "error" then
		return "error", row.health_detail or "git error"
	end
	if row.health == "drift" then
		return "drift", row.health_detail
	end
	local v = version_str(row)
	local rev = row.rev and row.rev:sub(1, 7) or "—"
	local detail = (v ~= "" and (v .. " · ") or "") .. rev
	if not row.active then
		return "inactive", detail .. " · not active"
	end
	return "active", detail
end

local function row_line(row, icons, name_width)
	local name = row.name:sub(1, name_width)
	return icons[row.state] .. " " .. name .. string.rep(" ", name_width - #name) .. row.detail
end

local function start_checks()
	for _, row in ipairs(state.rows) do
		pack.check(row, schedule_render)
	end
end

function M.render()
	if not float.is_open(state) then
		return
	end
	local o = opts()
	local win_id, buf = state.win, state.buf
	local cursor = vim.api.nvim_win_get_cursor(win_id)[1]

	local rows = state.rows
	for _, row in ipairs(rows) do
		row.state, row.detail = evaluate(row)
	end
	table.sort(rows, function(a, b)
		if STATE_ORDER[a.state] ~= STATE_ORDER[b.state] then
			return STATE_ORDER[a.state] < STATE_ORDER[b.state]
		end
		return a.name < b.name
	end)

	local counts = { active = 0, inactive = 0, drift = 0, missing = 0, error = 0 }
	for _, r in ipairs(rows) do
		counts[r.state] = counts[r.state] + 1
	end
	local summary = string.format(
		"%s %d active · %s %d inactive · %s %d drift · %s %d missing/error",
		o.icons.active,
		counts.active,
		o.icons.inactive,
		counts.inactive,
		o.icons.drift,
		counts.drift,
		o.icons.missing,
		counts.missing + counts.error
	)
	local hdr = string.format("%d plugins · %s", #rows, short_path(plug_dir(), o.width - 16))
	local footer = string.format(
		"%s details · %s source · %s/%s update · %s path · %s refresh · %s close",
		(table.concat(keys(o.keymaps.detail), " ")),
		(table.concat(keys(o.keymaps.source), " ")),
		(table.concat(keys(o.keymaps.update), " ")),
		(table.concat(keys(o.keymaps.update_all), " ")),
		(table.concat(keys(o.keymaps.yank_path), " ")),
		(table.concat(keys(o.keymaps.refresh), " ")),
		(table.concat(keys(o.keymaps.close), " "))
	)

	local lines = { summary, hdr }
	for _, row in ipairs(rows) do
		lines[#lines + 1] = row_line(row, o.icons, o.name_width)
	end
	lines[#lines + 1] = footer

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	local width = math.min(o.width, (vim.o.columns or 80) - 4)
	local max_height = type(o.max_height) == "function" and o.max_height() or o.max_height
	local height = math.min(#lines, math.max(6, max_height))
	local pos = float.center(width, height)
	vim.api.nvim_win_set_config(win_id, {
		relative = "editor",
		width = width,
		height = height,
		row = pos.row,
		col = pos.col,
	})

	-- dot = state color; detail/header/footer = dim
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	local detail_col = 1 + 1 + o.name_width
	for i, row in ipairs(rows) do
		local line = i + 1 -- 0-indexed: line 1 = summary, line 2 = header
		hl_range(buf, line, 0, 1, o.highlights[row.state])
		hl_range(buf, line, detail_col, detail_col + #row.detail, "Comment")
	end
	hl_range(buf, 1, 0, #hdr, "Comment")
	hl_range(buf, #lines - 1, 0, #footer, "Comment")

	if cursor > #lines then
		cursor = #lines
	end
	vim.api.nvim_win_set_cursor(win_id, { cursor, 0 })
end

--- Re-snapshot the plugin set and (re)run the on-disk checks.
function M.refresh()
	if not float.is_open(state) then
		return
	end
	local ok, rows = pcall(pack.list)
	if not ok then
		notify("vim.pack unavailable: " .. tostring(rows), vim.log.levels.ERROR)
		return
	end
	state.rows = rows
	M.render()
	start_checks()
end

local function close_detail()
	if state and state.detail and float.is_open(state.detail) then
		float.close(state.detail)
	end
	if state then
		state.detail = nil
	end
end

local function close()
	close_detail()
	if state then
		float.close(state) -- bufhidden=wipe cleans the buffer
		state = nil
	end
end

local function row_at_cursor()
	if not state then
		return
	end
	local line = vim.api.nvim_win_get_cursor(state.win)[1]
	return state.rows[line - 2] -- line 1 = summary, line 2 = header
end

local function status_of(row)
	if row.missing then
		return "missing"
	end
	if row.health == "error" then
		return "error"
	end
	if row.health == "drift" then
		return "revision drift"
	end
	return row.active and "active" or "inactive"
end

local function open_detail(row)
	close_detail()
	local info = pack.info(row)
	local branches = info and info.branches or {}
	local tags = info and info.tags or {}
	local lines = {
		row.name,
		"",
		"status    " .. status_of(row),
		"version   " .. (version_str(row) ~= "" and version_str(row) or "—"),
		"revision  " .. (row.rev or "—"),
		"source    " .. row.src,
		"path      " .. short_path(row.path, 70),
		"branches  " .. list(branches, 5),
		"tags      " .. list(tags, 6),
	}
	local width = 40
	for _, l in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth(l))
	end
	width = math.min(width + 4, (vim.o.columns or 80) - 4)
	local pos = float.center(width, #lines)
	local f = float.open({
		row = pos.row,
		col = pos.col,
		width = width,
		height = #lines,
		title = " plugin ",
		title_pos = "center",
		lines = lines,
	})
	vim.bo[f.buf].modifiable = false
	hl_range(f.buf, 0, 0, #row.name, "Title")
	state.detail = f
	for _, key in ipairs(keys(opts().keymaps.close)) do
		vim.keymap.set("n", key, close_detail, { buffer = f.buf, silent = true, desc = "Close" })
	end
end

local function action_source()
	local row = row_at_cursor()
	if not row then
		notify("No plugin on this line", vim.log.levels.WARN)
		return
	end
	vim.ui.open(row.src)
end

local function action_yank(field)
	local row = row_at_cursor()
	if not row then
		notify("No plugin on this line", vim.log.levels.WARN)
		return
	end
	local text = field == "src" and row.src or row.path
	vim.fn.setreg("+", text)
	notify("Yanked " .. text)
end

local function action_details()
	local row = row_at_cursor()
	if row then
		open_detail(row)
	end
end

--- Hand off to vim.pack's native confirmation buffer (`all` = every plugin).
local function action_update(all)
	local row = row_at_cursor()
	if not all and not row then
		notify("No plugin on this line", vim.log.levels.WARN)
		return
	end
	close()
	vim.pack.update(all and nil or { row.name })
end

local function setup_keymaps(buf)
	local o = opts()
	local function set(spec, rhs, desc)
		for _, key in ipairs(keys(spec)) do
			vim.keymap.set("n", key, rhs, { buffer = buf, silent = true, desc = desc })
		end
	end
	set(o.keymaps.close, close, "Close")
	set(o.keymaps.detail, action_details, "Details")
	set(o.keymaps.source, action_source, "Open source")
	set(o.keymaps.yank_path, function()
		action_yank("path")
	end, "Yank path")
	set(o.keymaps.yank_src, function()
		action_yank("src")
	end, "Yank source")
	set(o.keymaps.update, function()
		action_update(false)
	end, "Update plugin")
	set(o.keymaps.update_all, function()
		action_update(true)
	end, "Update all plugins")
	set(o.keymaps.refresh, M.refresh, "Refresh")
end

function M.is_active()
	return float.is_open(state)
end

function M.open()
	if float.is_open(state) then
		vim.api.nvim_set_current_win(state.win)
		M.refresh()
		return
	end
	local ok, rows = pcall(pack.list)
	if not ok then
		notify("vim.pack unavailable: " .. tostring(rows), vim.log.levels.ERROR)
		return
	end
	local o = opts()
	local width = math.min(o.width, (vim.o.columns or 80) - 4)
	local max_height = type(o.max_height) == "function" and o.max_height() or o.max_height
	local height = math.min(#rows + 3, math.max(6, max_height))
	local pos = float.center(width, height)
	local f = float.open({
		row = pos.row,
		col = pos.col,
		width = width,
		height = height,
		title = " Plugins ",
		title_pos = "center",
		cursorline = true,
	})
	state = { win = f.win, buf = f.buf, rows = rows, detail = nil }
	setup_keymaps(f.buf)
	M.render()
	start_checks()
end

function M.close()
	close()
end

function M.toggle()
	if float.is_open(state) then
		close()
	else
		M.open()
	end
end

return M
