--- Full-viewport, non-destructive file preview.
---
--- Owns one reusable `nofile` scratch buffer shown in a borderless float that
--- covers the area above the drawer. File contents are read from disk into the
--- scratch buffer; no file buffer is ever created (that only happens when the
--- user chooses an entry). The float is not focusable, so the input loop keeps
--- receiving keys.
---
--- To keep the "normal layout" look, the float starts below the tabline and
--- mirrors the editor's gutter/wrap options, so buffer tabs stay visible and
--- line numbers line up with regular windows.

local preview = require("ui.preview")
local buf = require("ui.buf")
local win = require("ui.win")

local M = {}

local P = { win = nil, buf = nil, path = nil }

local hl_ns = vim.api.nvim_create_namespace("loupe_preview_hl")

vim.api.nvim_set_hl(0, "LoupePreviewLine", { link = "CursorLine", default = true })
vim.api.nvim_set_hl(0, "LoupePreviewMatch", { link = "Search", default = true })

--- Rows occupied by the tabline (showtabline=2, or 1 with multiple tabs).
local function tabline_rows()
	if vim.o.showtabline == 2 then
		return 1
	end
	if vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1 then
		return 1
	end
	return 0
end

--- Top row and height of the region between the tabline and the drawer.
local function geometry(drawer_win)
	local top = tabline_rows()
	local row = vim.api.nvim_win_get_position(drawer_win)[1]
	return top, math.max(1, row - top)
end

local function set_lines(lines)
	vim.bo[P.buf].modifiable = true
	vim.api.nvim_buf_set_lines(P.buf, 0, -1, false, lines)
	vim.bo[P.buf].modifiable = false
end

--- Move the preview cursor to `lnum`/`col` (byte) and center it.
local function position(lnum, col)
	if not (P.win and vim.api.nvim_win_is_valid(P.win) and P.buf and vim.api.nvim_buf_is_valid(P.buf)) then
		return
	end
	local count = vim.api.nvim_buf_line_count(P.buf)
	local row = math.max(1, math.min(lnum or 1, count))
	local line = vim.api.nvim_buf_get_lines(P.buf, row - 1, row, false)[1] or ""
	local c = math.max(0, math.min(col or 0, #line))
	vim.api.nvim_win_set_cursor(P.win, { row, c })
	vim.api.nvim_win_call(P.win, function()
		vim.cmd("normal! zz")
	end)
end

--- Highlight the occurrence line and, when known, the exact match range.
local function highlight(lnum, col, col_end)
	if not (P.buf and vim.api.nvim_buf_is_valid(P.buf)) then
		return
	end
	vim.api.nvim_buf_clear_namespace(P.buf, hl_ns, 0, -1)
	if not lnum then
		return
	end
	local row = lnum - 1
	if row < 0 or row >= vim.api.nvim_buf_line_count(P.buf) then
		return
	end
	vim.api.nvim_buf_set_extmark(P.buf, hl_ns, row, 0, {
		line_hl_group = "LoupePreviewLine",
		priority = 50,
	})
	if col and col_end and col_end > col then
		local line = vim.api.nvim_buf_get_lines(P.buf, row, row + 1, false)[1] or ""
		local from = math.max(0, math.min(col, #line))
		local to = math.max(from, math.min(col_end, #line))
		if to > from then
			vim.api.nvim_buf_set_extmark(P.buf, hl_ns, row, from, {
				end_col = to,
				hl_group = "LoupePreviewMatch",
				priority = 200,
			})
		end
	end
end

--- Whether the preview float is currently open.
function M.is_open()
	return P.win ~= nil and vim.api.nvim_win_is_valid(P.win)
end

--- Window options to mirror for a normal-layout preview.
local function default_window_opts()
	local get = vim.api.nvim_get_option_value
	return {
		number = get("number", { scope = "global" }),
		relativenumber = get("relativenumber", { scope = "global" }),
		signcolumn = get("signcolumn", { scope = "global" }),
		wrap = get("wrap", { scope = "global" }),
		linebreak = get("linebreak", { scope = "global" }),
		list = get("list", { scope = "global" }),
	}
end

--- Open the float over the drawer. `drawer_win` determines the available rows.
function M.open(drawer_win, opts)
	opts = opts or default_window_opts()
	P.buf = buf.scratch({ bufhidden = "wipe" })

	local top, height = geometry(drawer_win)
	P.win = vim.api.nvim_open_win(P.buf, false, {
		relative = "editor",
		row = top,
		col = 0,
		width = vim.o.columns,
		height = height,
		border = "none",
		focusable = false,
		noautocmd = true,
		zindex = 200,
	})

	-- Mirror the editor's window options so the preview looks like a normal
	-- buffer view (same gutter padding, numbers, wrapping).
	win.set(P.win, {
		number = opts.number,
		relativenumber = opts.relativenumber,
		signcolumn = opts.signcolumn,
		wrap = opts.wrap,
		linebreak = opts.linebreak,
		list = opts.list,
		foldenable = false,
		cursorline = false,
		scrolloff = 0,
		winhighlight = "Normal:Normal",
	})
end

--- Open the preview if it isn't already showing.
function M.ensure_open(drawer_win, opts)
	if not M.is_open() then
		M.open(drawer_win, opts)
	end
end

--- Re-fit the float after a resize.
function M.resize(drawer_win)
	if not M.is_open() then
		return
	end
	local top, height = geometry(drawer_win)
	vim.api.nvim_win_set_config(P.win, {
		relative = "editor",
		row = top,
		col = 0,
		width = vim.o.columns,
		height = height,
	})
end

--- Render `path` into the preview buffer, jumping to `opts.lnum`/`opts.col`.
function M.show(path, opts)
	opts = opts or {}
	if not (P.buf and vim.api.nvim_buf_is_valid(P.buf)) then
		return
	end

	local lnum = opts.lnum or 1
	local col = opts.col or 0

	-- Same file already rendered: reposition without re-reading it.
	if path == P.path then
		position(lnum, col)
		highlight(opts.lnum, opts.col, opts.col_end)
		return
	end
	P.path = path
	local max_lines = opts.max_lines or 2000

	if preview.is_text(path) == false then
		set_lines({ "-binary file-" })
		position(1, 0)
		highlight(nil)
		return
	end

	local lines, _, truncated = preview.read(path, max_lines)
	if not lines then
		set_lines({ "-cannot read file-" })
		position(1, 0)
		highlight(nil)
		return
	end
	if truncated then
		lines[#lines + 1] = ""
		lines[#lines + 1] = ("-- truncated at %d lines --"):format(max_lines)
	end

	set_lines(lines)

	if preview.should_highlight(P.buf) then
		preview.highlight(P.buf, vim.filetype.match({ filename = path }) or "")
	end
	position(lnum, col)
	highlight(opts.lnum, opts.col, opts.col_end)
end

--- Current topline of the preview (nil when closed).
function M.topline()
	if not M.is_open() then
		return nil
	end
	return vim.api.nvim_win_call(P.win, function()
		return vim.fn.line("w0")
	end)
end

--- Clear the preview (no selection).
function M.clear()
	P.path = nil
	if P.buf and vim.api.nvim_buf_is_valid(P.buf) then
		set_lines({})
	end
end

--- Tear down the float and wipe the buffer.
function M.close()
	if M.is_open() then
		vim.api.nvim_win_close(P.win, true)
	end
	P.win = nil
	if P.buf and vim.api.nvim_buf_is_valid(P.buf) then
		pcall(vim.api.nvim_buf_delete, P.buf, { force = true })
	end
	P.buf = nil
	P.path = nil
end

return M
