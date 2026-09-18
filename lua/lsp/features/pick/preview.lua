--- Preview helpers shared by the LSP symbol pickers.
---
--- Bounded context around the symbol under a header line, theme-aware syntax
--- colors, current-line + name-span highlights, and the target line centered.

local hl = require("ui.hl")
local preview = require("ui.preview")
local nav = require("lsp.features.pick.nav")

local M = {}

local preview_ns = vim.api.nvim_create_namespace("lsp_pick_preview")

--- Context lines shown around the symbol's line in the preview.
local function n_context()
	return 2 * vim.o.lines
end

--- Preview header: file:line, kind, name (with parent chain when present).
local function title(v)
	local filename = v.filename
	if not filename and v.buf then
		filename = vim.api.nvim_buf_get_name(v.buf)
	end
	local rel = filename and filename ~= "" and vim.fn.fnamemodify(filename, ":~:.") or "?"
	local parts = { rel .. ":" .. (v.range.start.line + 1) }
	if v.kind_label and v.kind_label ~= "" then
		parts[#parts + 1] = v.kind_label
	end
	local name = v.name or ""
	if v.container and v.container ~= "" then
		name = name .. " (" .. v.container .. ")"
	end
	if name ~= "" then
		parts[#parts + 1] = name
	end
	return table.concat(parts, "  ")
end

--- Byte columns of the symbol's name span within preview row (clamped to the
--- line). Returns nil when the span is empty or absent.
local function region_cols(buf_id, row, range, enc)
	local line = vim.api.nvim_buf_get_lines(buf_id, row, row + 1, false)[1] or ""
	local line_len = #line
	local start_col =
		math.min(nav.lsp_col_to_byte(buf_id, { line = row, character = range.start.character or 0 }, enc), line_len)
	local end_col
	if range["end"] and range["end"].line == range.start.line then
		end_col = math.min(
			nav.lsp_col_to_byte(buf_id, { line = row, character = range["end"].character or 0 }, enc),
			line_len
		)
	else
		end_col = line_len
	end
	if end_col <= start_col then
		return nil
	end
	return start_col, end_col
end

--- Shared preview: bounded context around the symbol under a header line,
--- theme-aware syntax colors, current-line + name-span highlights, and the
--- target line centered in the window.
function M.preview_symbol(buf_id, item)
	local v = item.value
	if not v.range then
		vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { item.text or "" })
		return
	end
	local lnum = v.range.start.line
	local n_ctx = n_context()
	local lines, hl_row, ft

	if v.filename and (not v.buf or vim.api.nvim_buf_get_name(v.buf) ~= v.filename) then
		-- Cross-file (workspace picker): bounded read around the target line.
		local head = title(v)
		if preview.is_text(v.filename) == false then
			vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { head, "-Non-text-file-" })
			return
		end
		local file_lines = preview.read(v.filename, lnum + 1 + n_ctx)
		if not file_lines then
			vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { head, "-No-access-" })
			return
		end
		local from = math.max(1, lnum + 1 - n_ctx)
		lines = vim.list_slice(file_lines, from)
		hl_row = lnum + 2 - from
		ft = vim.filetype.match({ filename = v.filename })
	else
		-- Current buffer: read a window around the target line.
		local buf = v.buf or vim.api.nvim_get_current_buf()
		local count = vim.api.nvim_buf_line_count(buf)
		local from = math.max(0, lnum - n_ctx)
		lines = vim.api.nvim_buf_get_lines(buf, from, math.min(count, lnum + n_ctx + 1), false)
		hl_row = lnum - from + 1
		ft = vim.bo[buf].filetype
	end
	if #lines == 0 then
		vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { title(v) })
		return
	end
	table.insert(lines, 1, title(v))
	hl_row = math.max(1, math.min(hl_row, #lines - 1))

	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
	if preview.should_highlight(buf_id) then
		preview.highlight(buf_id, ft)
	end
	vim.api.nvim_buf_clear_namespace(buf_id, preview_ns, 0, -1)
	hl.eol(buf_id, preview_ns, 0, 0, "MiniPickHeader", { priority = 200 })
	hl.eol(buf_id, preview_ns, hl_row, 0, "MiniPickPreviewLine", { priority = 201 })
	local col_start, col_end = region_cols(buf_id, hl_row, v.range, v.offset_encoding or "utf-16")
	if col_start then
		hl.range(buf_id, preview_ns, hl_row, col_start, col_end, "MiniPickPreviewRegion", { priority = 202 })
	end

	-- Center the target line when the preview buffer is displayed.
	local win = vim.fn.bufwinid(buf_id)
	if win ~= -1 then
		vim.api.nvim_win_set_cursor(win, { hl_row + 1, col_start or 0 })
		pcall(vim.api.nvim_win_call, win, function()
			vim.cmd("normal! zz")
		end)
	end
end

return M
