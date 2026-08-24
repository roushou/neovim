--- keyd: own keymap-reveal plugin (v1: normal mode only).
---
--- Trigger keys open a float listing mappings that start with the typed
--- prefix; typing more filters, <CR> executes, <BS> pops, <Esc>/<C-c>
--- cancels, <C-d>/<C-u> scroll. The window appears only after a pause
--- (SHOW_DELAY), so fast key sequences don't flash it.
---
--- Execution: the full key sequence is re-fed with the trigger temporarily
--- unmapped and re-mapped on the next tick, which avoids infinite recursion
--- while letting the real mapping run.

local map = require("util").map

local M = {}

-- Trigger keys (raw). `z` is omitted: nvim_get_keymap() only returns
-- user mappings, and there are none under `z` in this config.
local TRIGGERS = { " ", "g", "[", "]" }

-- Show the window only after this pause (ms); 0 = always show immediately.
local SHOW_DELAY = 400

local ns = vim.api.nvim_create_namespace("keyd")

-- active query state; nil when idle
local state = nil -- { query, buf_id, trigger, win, buf, clues }

-- guard against the re-fed trigger re-entering during execution
local in_exec = false

local function raw(keys)
	return vim.api.nvim_replace_termcodes(keys, true, false, true)
end

local CR = raw("<CR>")
local BS = raw("<BS>")
local ESC = raw("<Esc>")
local C_C = raw("<C-c>")
local CD = raw("<C-d>")
local CU = raw("<C-u>")

-- getcharstr() blocks nvim's redraw; a repeating timer keeps the float
-- repainting while we wait (the same trick used by other keymap-reveal
-- tools).
local redraw_timer = vim.loop.new_timer()
local function getchar()
	redraw_timer:start(
		0,
		50,
		vim.schedule_wrap(function()
			if state and state.win and vim.api.nvim_win_is_valid(state.win) then
				vim.cmd("redraw")
			end
		end)
	)
	local ok, key = pcall(vim.fn.getcharstr)
	redraw_timer:stop()
	return ok and key or nil
end

-- persistent timer for the show delay (works while getcharstr is blocking)
local show_timer = vim.loop.new_timer()

local function setup_hl()
	vim.api.nvim_set_hl(0, "KeydNextKey", {
		fg = vim.api.nvim_get_hl(0, { name = "Function" }).fg or 0xffffff,
		bold = true,
	})
	vim.api.nvim_set_hl(0, "KeydDesc", {
		fg = vim.api.nvim_get_hl(0, { name = "Comment" }).fg or 0xaaaaaa,
	})
end
vim.api.nvim_create_autocmd("ColorScheme", { callback = setup_hl })

--- Mappings for a buffer, keyed by raw lhs (buffer-local wins over global).
local function clues_get_all(buf_id)
	local clues = {}
	local function add(maps)
		for _, m in ipairs(maps) do
			local lhs = raw(m.lhs)
			if lhs ~= "" and m.rhs ~= "<Nop>" and not vim.tbl_contains(TRIGGERS, lhs) then
				local desc = m.desc
				if not desc or desc == "" then
					local rhs = m.rhs or ""
					desc = rhs ~= "" and vim.fn.keytrans(rhs) or "(lua)"
				end
				clues[lhs] = desc
			end
		end
	end
	add(vim.api.nvim_get_keymap("n"))
	add(vim.api.nvim_buf_get_keymap(buf_id, "n"))
	return clues
end

local function filter_clues(buf_id, query)
	local all = clues_get_all(buf_id)
	local q = table.concat(query, "")
	for lhs in pairs(all) do
		if lhs:sub(1, #q) ~= q then
			all[lhs] = nil
		end
	end
	return all
end

local function close_window()
	if state and state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true) -- bufhidden=wipe cleans the buffer
	end
	state.win, state.buf = nil, nil
end

local function window_open()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		anchor = "SE",
		-- row/col are offsets from the editor's TOP-LEFT; anchor="SE" places
		-- the window's bottom-right corner there, so point it at the
		-- bottom-right corner minus a 1-cell margin.
		row = math.max(0, (vim.o.lines or 24) - 2),
		col = math.max(0, (vim.o.columns or 80) - 2),
		width = 40,
		height = 3,
		border = "single",
		title = " " .. vim.fn.keytrans(table.concat(state.query, "")) .. " ",
		title_pos = "left",
		noautocmd = true, -- don't fire BufEnter (trigger mapping autocmd) for the float
	})
	vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
	state.win, state.buf = win, buf
end

local function render()
	if not state or not state.win or not vim.api.nvim_win_is_valid(state.win) then
		return
	end
	local win, buf = state.win, state.buf
	local q = table.concat(state.query, "")

	local rows = {}
	for lhs, desc in pairs(state.clues) do
		rows[#rows + 1] = { rest = lhs:sub(#q + 1), desc = desc }
	end
	table.sort(rows, function(a, b)
		return a.rest < b.rest
	end)
	if #rows == 0 then
		close_window()
		return
	end

	local maxk = 0
	for _, r in ipairs(rows) do
		maxk = math.max(maxk, #vim.fn.keytrans(r.rest))
	end
	maxk = math.min(maxk, 14)

	local lines = {}
	for _, r in ipairs(rows) do
		local k = vim.fn.keytrans(r.rest)
		if #k > maxk then
			k = k:sub(1, maxk - 1) .. "…"
		end
		lines[#lines + 1] = " " .. k .. string.rep(" ", maxk - #k + 2) .. r.desc
	end

	local width = math.min(72, math.max(#lines[1] or 20, 24), (vim.o.columns or 80) - 4)
	local height = math.min(#lines, 16)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for i, r in ipairs(rows) do
		local k = vim.fn.keytrans(r.rest)
		if #k > maxk then
			k = k:sub(1, maxk - 1) .. "…"
		end
		vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 1, { hl_group = "KeydNextKey", end_col = 1 + #k })
	end
	vim.api.nvim_win_set_config(win, {
		relative = "editor",
		anchor = "SE",
		-- row/col are offsets from the editor's TOP-LEFT; anchor="SE" places
		-- the window's bottom-right corner there, so point it at the
		-- bottom-right corner minus a 1-cell margin.
		row = math.max(0, (vim.o.lines or 24) - 2),
		col = math.max(0, (vim.o.columns or 80) - 2),
		width = width,
		height = height,
	})
	vim.cmd("redraw")
end

-- Re-feed the typed sequence so the real mapping runs. The trigger must be
-- out of the way while the keys process, or it would start a new query
-- (infinite recursion); re-map it once the keys can no longer trigger it.
local trigger_rhs -- forward-declared: exec and trigger_rhs call each other

local function exec()
	local trigger = state.trigger
	local buf_id = state.buf_id
	local q = table.concat(state.query, "")
	local count = vim.v.count > 0 and tostring(vim.v.count) or ""
	local keys = count .. q
	if vim.v.register ~= '"' then
		keys = '"' .. vim.v.register .. keys
	end

	close_window()
	state = nil

	in_exec = true
	vim.schedule(function()
		in_exec = false
	end)
	pcall(vim.keymap.del, "n", vim.fn.keytrans(trigger), { buffer = buf_id })
	vim.api.nvim_feedkeys(keys, "mit", false)
	vim.schedule(function()
		map("n", vim.fn.keytrans(trigger), trigger_rhs(trigger), {
			buffer = buf_id,
			nowait = true,
			desc = "Keyd: " .. vim.fn.keytrans(trigger),
		})
	end)
end

trigger_rhs = function(trigger)
	return function()
		if in_exec then
			in_exec = false
			return
		end
		if vim.bo.filetype == "ministarter" then
			return
		end
		setup_hl()

		local buf_id = vim.api.nvim_get_current_buf()
		state = { query = { trigger }, buf_id = buf_id, trigger = trigger, win = nil, buf = nil }
		state.clues = filter_clues(buf_id, state.query)

		-- show the window only after a pause (schedule-wrapped: buffer/window
		-- work is not allowed in the timer's fast event context)
		show_timer:start(
			SHOW_DELAY,
			0,
			vim.schedule_wrap(function()
				if state and not state.win then
					window_open()
					render()
				end
			end)
		)

		while state do
			local key = getchar()
			show_timer:stop()
			if key == nil or key == ESC or key == C_C then
				close_window()
				state = nil
				return
			end
			if key == CD or key == CU then
				if state.win and vim.api.nvim_win_is_valid(state.win) then
					local n = vim.api.nvim_buf_line_count(state.buf)
					local cur = vim.api.nvim_win_get_cursor(state.win)[1]
					local step = key == CD and 5 or -5
					vim.api.nvim_win_set_cursor(state.win, { math.max(1, math.min(n, cur + step)), 0 })
					vim.cmd("redraw")
				end
				goto continue
			end
			if key == CR then
				exec()
				return
			end
			if key == BS then
				if #state.query <= 1 then
					close_window()
					state = nil
					return
				end
				table.remove(state.query)
			else
				table.insert(state.query, key)
			end
			state.clues = filter_clues(state.buf_id, state.query)

			local q = table.concat(state.query, "")
			local count = 0
			for _ in pairs(state.clues) do
				count = count + 1
			end
			if count == 0 or (count == 1 and state.clues[q]) then
				exec()
				return
			end
			if state.win and vim.api.nvim_win_is_valid(state.win) then
				render()
			end
			::continue::
		end
	end
end

local function map_triggers(buf)
	if vim.b[buf].keyd_attached then
		return
	end
	vim.b[buf].keyd_attached = true
	if vim.bo[buf].filetype == "ministarter" then
		return
	end
	for _, t in ipairs(TRIGGERS) do
		map("n", vim.fn.keytrans(t), trigger_rhs(t), {
			buffer = buf,
			nowait = true,
			desc = "Keyd: " .. vim.fn.keytrans(t),
		})
	end
end

-- triggers are buffer-local; install on every buffer as it's entered
vim.api.nvim_create_autocmd("BufEnter", {
	desc = "Install keyd triggers",
	callback = function()
		map_triggers(vim.api.nvim_get_current_buf())
	end,
})
for _, b in ipairs(vim.api.nvim_list_bufs()) do
	map_triggers(b)
end

return M
