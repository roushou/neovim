--- Custom `:LspInfo` replacement (nvim-lspconfig's UI without the plugin).
---
--- Shows every LSP server that is either configured via |vim.lsp.config()| or
--- currently running (clients started externally, e.g. rustaceanvim), with its
--- state: connected / starting / idle / cmd missing / disabled.
---
--- Keymaps (in the float):
---   r        restart server under cursor
---   s        stop running clients under cursor (keeps it enabled)
---   e        enable / (re)start server under cursor
---   d        disable server under cursor (stops clients)
---   <CR>     jump to first buffer attached to server under cursor
---   R        refresh
---   q/<Esc>  close

local map = require("util").map

local M = {}

local ns = vim.api.nvim_create_namespace("lspinfo")

-- open float state
local state = nil -- { win, buf, open_buf, rows }

local NAME_WIDTH = 18
local FLOAT_WIDTH = 76

local STATE_ORDER = { connected = 0, starting = 1, idle = 2, missing = 3, disabled = 4 }

local DOTS = {
	connected = "●",
	starting = "◐",
	idle = "○",
	missing = "✗",
	disabled = "○",
}

-- theme-aware highlight groups (kanagawa sets these)
local HL = {
	connected = "DiagnosticOk",
	starting = "DiagnosticWarn",
	idle = "Comment",
	missing = "DiagnosticError",
	disabled = "Comment",
}

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

--- Resolve a row's state, detail string and attached buffers.
--- @param row table
local function evaluate(row)
	local clients = row.clients
	if #clients > 0 then
		local buffers = {}
		for _, c in ipairs(clients) do
			if c.initialized then
				for b in pairs(c.attached_buffers) do
					buffers[#buffers + 1] = b
				end
			end
		end
		if #buffers > 0 then
			table.sort(buffers)
			local root = ""
			for _, c in ipairs(clients) do
				if c.initialized and c.root_dir then
					root = short_path(c.root_dir, 34)
					break
				end
			end
			local n = #buffers
			local detail = string.format("%d buf%s", n, n == 1 and "" or "s")
			if root ~= "" then
				detail = detail .. " · " .. root
			end
			return "connected", detail, buffers
		end
		return "starting", "starting…", {}
	end

	local config = row.config
	if not config then
		return "idle", "no config (started externally)", {}
	end
	if not vim.lsp.is_enabled(row.name) then
		return "disabled", "disabled (vim.lsp.enable)", {}
	end
	local cmd = config.cmd
	if type(cmd) == "table" and cmd[1] and vim.fn.executable(cmd[1]) == 0 then
		return "missing", "cmd not found: " .. cmd[1], {}
	end
	return "idle", "idle (enabled)", {}
end

--- All configured servers + orphan clients, evaluated and sorted.
local function collect()
	local configs = vim.lsp.get_configs()
	local clients = vim.lsp.get_clients({ _uninitialized = true })

	local by_name = {}
	for _, c in ipairs(clients) do
		by_name[c.name] = by_name[c.name] or {}
		table.insert(by_name[c.name], c)
	end

	local rows, seen = {}, {}
	for _, config in ipairs(configs) do
		seen[config.name] = true
		table.insert(rows, { name = config.name, config = config, clients = by_name[config.name] or {} })
	end
	-- Clients started outside vim.lsp.config (rustaceanvim, manual vim.lsp.start).
	for name, cs in pairs(by_name) do
		if not seen[name] then
			table.insert(rows, { name = name, config = nil, clients = cs })
		end
	end

	for _, row in ipairs(rows) do
		row.state, row.detail, row.buffers = evaluate(row)
	end

	table.sort(rows, function(a, b)
		if STATE_ORDER[a.state] ~= STATE_ORDER[b.state] then
			return STATE_ORDER[a.state] < STATE_ORDER[b.state]
		end
		return a.name < b.name
	end)
	return rows
end

local function row_line(row)
	local name = row.name:sub(1, NAME_WIDTH)
	return DOTS[row.state] .. " " .. name .. string.rep(" ", NAME_WIDTH - #name) .. row.detail
end

local function render()
	if not state or not vim.api.nvim_win_is_valid(state.win) then
		return
	end
	local win, buf = state.win, state.buf
	local cursor = vim.api.nvim_win_get_cursor(win)[1]

	local rows = collect()
	state.rows = rows

	local counts = { connected = 0, starting = 0, idle = 0, missing = 0, disabled = 0 }
	for _, r in ipairs(rows) do
		counts[r.state] = counts[r.state] + 1
	end
	local summary = string.format(
		"● %d connected · ◐ %d starting · ○ %d idle · ✗ %d cmd missing",
		counts.connected,
		counts.starting,
		counts.idle,
		counts.missing
	)

	local open_buf = state.open_buf
	if not vim.api.nvim_buf_is_valid(open_buf) then
		open_buf = vim.api.nvim_get_current_buf()
	end
	local bname = vim.api.nvim_buf_get_name(open_buf)
	if bname == "" then
		bname = "[no name]"
	else
		bname = vim.fn.fnamemodify(bname, ":t")
	end
	local attached = {}
	for _, c in ipairs(vim.lsp.get_clients({ bufnr = open_buf, _uninitialized = true })) do
		attached[#attached + 1] = c.name
	end
	local hdr = string.format("buf %d · %s", open_buf, bname)
	if #attached > 0 then
		hdr = hdr .. " · attached: " .. table.concat(attached, ", ")
	end

	local lines = { summary, hdr }
	for _, row in ipairs(rows) do
		lines[#lines + 1] = row_line(row)
	end
	lines[#lines + 1] = "r restart · s stop · e enable/start · d disable · ⏎ jump · R refresh · q close"

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	local height = math.min(#lines, math.max(4, (vim.o.lines or 24) - 10))
	local width = math.min(FLOAT_WIDTH, (vim.o.columns or 80) - 4)
	vim.api.nvim_win_set_config(win, {
		relative = "editor",
		width = width,
		height = height,
		row = math.max(0, math.floor(((vim.o.lines or 24) - height) / 2)),
		col = math.max(0, math.floor(((vim.o.columns or 80) - width) / 2)),
	})

	-- recolor: dot = state color, detail = dim
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	local detail_col = 1 + 1 + NAME_WIDTH -- dot + space + name
	for i, row in ipairs(rows) do
		local line = i + 1 -- 0-indexed: lines[1] is summary, lines[2] is header
		vim.api.nvim_buf_set_extmark(buf, ns, line, 0, { hl_group = HL[row.state], end_col = 1 })
		vim.api.nvim_buf_set_extmark(buf, ns, line, detail_col, {
			hl_group = "Comment",
			end_col = detail_col + #row.detail,
		})
	end

	-- restore cursor (buffer was rewritten)
	if cursor > #lines then
		cursor = #lines
	end
	vim.api.nvim_win_set_cursor(win, { cursor, 0 })
end

local function close()
	if not state then
		return
	end
	if vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true) -- bufhidden=wipe cleans the buffer
	end
	state = nil
end

local function row_at_cursor()
	if not state then
		return
	end
	local line = vim.api.nvim_win_get_cursor(state.win)[1]
	return state.rows[line - 2] -- line 1 = summary, line 2 = header
end

local function refresh(after)
	vim.defer_fn(function()
		if state and vim.api.nvim_win_is_valid(state.win) then
			render()
		end
	end, after or 250)
end

local function action_restart()
	local row = row_at_cursor()
	if not row then
		vim.notify("No server on this line", vim.log.levels.WARN)
		return
	end
	local restarted = false
	for _, c in ipairs(row.clients) do
		if not c:is_stopped() then
			c:_restart() -- mirrors `:lsp restart`
			restarted = true
		end
	end
	if not restarted then
		if row.config then
			vim.lsp.enable(row.name) -- (re)starts on matching buffers
		else
			vim.notify(row.name .. ": no running client to restart", vim.log.levels.WARN)
			return
		end
	end
	refresh()
end

local function action_stop()
	local row = row_at_cursor()
	if not row then
		vim.notify("No server on this line", vim.log.levels.WARN)
		return
	end
	local stopped = 0
	for _, c in ipairs(row.clients) do
		if not c:is_stopped() then
			c:stop() -- graceful; will restart on matching buffers if still enabled
			stopped = stopped + 1
		end
	end
	if stopped == 0 then
		vim.notify(row.name .. ": no running client", vim.log.levels.WARN)
	end
	refresh()
end

local function action_enable()
	local row = row_at_cursor()
	if not row then
		vim.notify("No server on this line", vim.log.levels.WARN)
		return
	end
	if not row.config then
		vim.notify(row.name .. " has no vim.lsp.config entry (started externally)", vim.log.levels.WARN)
		return
	end
	if vim.lsp.is_enabled(row.name) then
		vim.notify(row.name .. " already enabled — starts on matching files", vim.log.levels.INFO)
	else
		vim.lsp.enable(row.name)
	end
	refresh(400)
end

local function action_disable()
	local row = row_at_cursor()
	if not row then
		vim.notify("No server on this line", vim.log.levels.WARN)
		return
	end
	if not row.config then
		vim.notify(row.name .. " has no vim.lsp.config entry (started externally)", vim.log.levels.WARN)
		return
	end
	vim.lsp.enable(row.name, false) -- stops clients + removes from enabled
	refresh(400)
end

local function action_jump()
	local row = row_at_cursor()
	if not row then
		return
	end
	local buffers = row.buffers or {}
	if #buffers == 0 then
		vim.notify(row.name .. ": no attached buffers", vim.log.levels.INFO)
		return
	end
	close()
	vim.api.nvim_set_current_buf(buffers[1])
end

local function setup_keymaps(buf)
	map("n", "q", close, { buf = buf })
	map("n", "<Esc>", close, { buf = buf })
	map("n", "r", action_restart, { buf = buf })
	map("n", "s", action_stop, { buf = buf })
	map("n", "e", action_enable, { buf = buf })
	map("n", "d", action_disable, { buf = buf })
	map("n", "<CR>", action_jump, { buf = buf })
	map("n", "R", render, { buf = buf })
end

function M.open()
	if state and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_set_current_win(state.win)
		render()
		return
	end

	local open_buf = vim.api.nvim_get_current_buf()
	local buf = vim.api.nvim_create_buf(false, true) -- scratch, unlisted
	vim.bo[buf].bufhidden = "wipe"

	local width = math.min(FLOAT_WIDTH, (vim.o.columns or 80) - 4)
	local height = math.min(#collect() + 3, math.max(5, (vim.o.lines or 24) - 10))
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = math.max(0, math.floor(((vim.o.lines or 24) - height) / 2)),
		col = math.max(0, math.floor(((vim.o.columns or 80) - width) / 2)),
		width = width,
		height = height,
		border = "single",
		title = " LSP clients ",
		title_pos = "center",
	})
	vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
	vim.wo[win].cursorline = true

	state = { win = win, buf = buf, open_buf = open_buf, rows = {} }
	setup_keymaps(buf)
	render()

	-- keep state fresh while open (starting → connected transitions)
	vim.defer_fn(function()
		if state and vim.api.nvim_win_is_valid(state.win) then
			render()
			vim.defer_fn(function()
				if state and vim.api.nvim_win_is_valid(state.win) then
					render()
				end
			end, 1500)
		end
	end, 500)
end

function M.close()
	close()
end

vim.api.nvim_create_user_command("LspInfo", function()
	M.open()
end, { desc = "Show LSP client status overview" })

return M
