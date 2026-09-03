--- Shared machinery for the LSP symbol pickers: decorations, choose/preview,
--- quickfix collection and mini.pick helpers.

local hl = require("ui.hl")

local M = {}

-- namespaces for icon + dimmed-tail + preview-line highlights on top of
-- mini.pick's render
local icon_ns = vim.api.nvim_create_namespace("lsp_pick_icons")
local dim_ns = vim.api.nvim_create_namespace("lsp_pick_dim")
local preview_ns = vim.api.nvim_create_namespace("lsp_pick_preview")

local function pick()
	return require("mini.pick")
end

--- LSP kind icon + theme-aware highlight group (MiniIcons* links to theme
--- groups like DiagnosticWarn / Constant / Function, so colors follow the
--- active colorscheme).
local function lsp_icon_data(kind)
	if not kind then
		return "•", "Comment"
	end
	local icon, hl = require("mini.icons").get("lsp", vim.lsp.protocol.SymbolKind[kind])
	return icon or "•", hl
end

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO)
end

--- Width of symbol-picker floats (0.75 of the screen), shared by both
--- pickers; also the right-alignment target for rendered lines.
local function pick_float_width()
	return math.floor(0.75 * vim.o.columns)
end

--- Float window config for both pickers: wide and horizontally centered
--- (mini.pick defaults to a bottom-left float).
local function symbol_window_config()
	local width = pick_float_width()
	return {
		width = width,
		col = math.max(0, math.floor((vim.o.columns - width) / 2)),
	}
end

--- Extmarks on top of default_show's render: kind-colored icon, dimmed
--- tree-guide rail (doc picker) and dimmed tail (container/file:line).
--- Priorities sit below MiniPickMatchRanges (200) and MiniPickMatchCurrent.
local function apply_symbol_decorations(buf_id, items)
	vim.api.nvim_buf_clear_namespace(buf_id, icon_ns, 0, -1)
	vim.api.nvim_buf_clear_namespace(buf_id, dim_ns, 0, -1)
	for i, item in ipairs(items) do
		local v = item.value
		if v then
			if v.icon_hl and v.icon_text then
				local col = v.icon_col or 0
				hl.range(buf_id, icon_ns, i - 1, col, col + #v.icon_text, v.icon_hl, { priority = 160 })
			end
			if v.guide and #v.guide > 0 then
				hl.range(buf_id, dim_ns, i - 1, 0, #v.guide, "Comment", { priority = 150 })
			end
			if v.dim_col then
				hl.eol(buf_id, dim_ns, i - 1, v.dim_col, "Comment", { priority = 150 })
			end
		end
	end
end

--- mini.pick render wrapper for workspace items (icon + container + file:line
--- already baked into `text`, so matching can target the path too).
local function symbol_show(buf_id, items, query, opts)
	require("mini.pick").default_show(buf_id, items, query, opts)
	apply_symbol_decorations(buf_id, items)
end

--- Byte column of an LSP position within a buffer's line (uses the public
--- vim.str_byteindex, not vim.lsp.util private API).
local function lsp_col_to_byte(buf, pos, enc)
	local line = vim.api.nvim_buf_get_lines(buf, pos.line, pos.line + 1, false)[1] or ""
	return vim.str_byteindex(line, enc, pos.character or 0, false)
end

--- Switch a window to the file's buffer, reusing an already-open buffer
--- (even a modified one) instead of :edit, which would reload it from disk.
local function edit_file_in_win(win, path)
	if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == path then
		return
	end
	local buf = vim.fn.bufadd(path)
	vim.api.nvim_win_set_buf(win, buf)
	vim.bo[buf].buflisted = true
end

--- Shared choose: jump to item.value.range.start in the picker's target
--- window (cross-file symbols switch the window to the file's buffer, keeping
--- an already-open modified buffer intact). Marks the previous position (''),
--- then opens folds and centers the jump (mirrors mini.pick's choose flow).
local function choose_symbol(item)
	local v = item.value
	if not v.range then
		return true -- placeholder (search hint / error message): keep picker open
	end
	local win = pick().get_picker_state().windows.target
	vim.api.nvim_win_call(win, function()
		vim.cmd("normal! m'")
		if v.filename then
			edit_file_in_win(win, v.filename)
		end
		local pos = v.range.start
		local col = lsp_col_to_byte(0, pos, v.offset_encoding or "utf-16")
		vim.api.nvim_win_set_cursor(0, { pos.line + 1, col })
		vim.cmd("normal! zvzz")
	end)
end

--- Byte column (1-based) of a symbol's start for quickfix entries; converted
--- from LSP character offsets via the item's offset encoding.
local function qf_col(v)
	local pos = v.range.start
	local enc = v.offset_encoding or "utf-16"
	local line
	if v.filename then
		local read = vim.fn.readfile(v.filename, "", pos.line + 1)
		line = read and read[pos.line + 1] or ""
	else
		local buf = v.buf or vim.api.nvim_get_current_buf()
		line = vim.api.nvim_buf_get_lines(buf, pos.line, pos.line + 1, false)[1] or ""
	end
	return vim.str_byteindex(line, enc, pos.character or 0, false) + 1
end

--- Choose marked items: collect them into a quickfix list (file/bufnr, lnum,
--- byte col, symbol name). Keeps the picker open when nothing was markable.
local function choose_symbols_marked(items_marked)
	local entries = {}
	for _, item in ipairs(items_marked) do
		local v = item.value
		if v and v.range then
			local entry
			if v.filename then
				entry = {
					filename = v.filename,
					lnum = v.range.start.line + 1,
					col = qf_col(v),
					text = v.name or v.rel or "",
				}
			elseif v.buf then
				entry = {
					bufnr = v.buf,
					lnum = v.range.start.line + 1,
					col = qf_col(v),
					text = v.name or "",
				}
			end
			if entry then
				entries[#entries + 1] = entry
			end
		end
	end
	if #entries == 0 then
		return true
	end
	vim.fn.setqflist({}, " ", { items = entries, title = "LSP symbols", nr = "$" })
	vim.schedule(function()
		vim.cmd("copen")
	end)
end

--- Highlight a preview scratch buffer: treesitter when a parser is available,
--- else native Vim syntax (mirrors mini.pick's preview_set_lines).
local function highlight_preview(buf_id, ft)
	if not ft then
		return
	end
	local has_lang, lang = pcall(vim.treesitter.language.get_lang, ft)
	lang = has_lang and lang or ft
	local has_parser, parser = pcall(vim.treesitter.get_parser, buf_id, lang, { error = false })
	has_parser = has_parser and parser ~= nil
	if has_parser then
		has_parser = pcall(vim.treesitter.start, buf_id, lang)
	end
	if not has_parser then
		vim.bo[buf_id].syntax = ft
	end
end

-- Skip highlighting for huge previews (same bounds as mini.pick).
local function preview_should_highlight(buf_id)
	local n = vim.api.nvim_buf_line_count(buf_id)
	local size = vim.api.nvim_buf_get_offset(buf_id, n)
	return size <= 1000000 and size <= 1000 * n
end

--- Context lines shown around the symbol's line in the preview.
local function preview_n_context()
	return 2 * vim.o.lines
end

--- True if the file has no NUL byte in its first chunk (mirrors mini.pick's
--- is_file_text); nil when the file can't be opened.
local function is_file_text(path)
	local fd = vim.uv.fs_open(path, "r", 438)
	if not fd then
		return nil
	end
	local data = vim.uv.fs_read(fd, 1024) or ""
	vim.uv.fs_close(fd)
	return not data:find("\0")
end

--- Preview header: file:line, kind, name (with parent chain when present).
local function preview_title(v)
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
local function preview_region_cols(buf_id, row, range, enc)
	local line = vim.api.nvim_buf_get_lines(buf_id, row, row + 1, false)[1] or ""
	local line_len = #line
	local start_col =
		math.min(lsp_col_to_byte(buf_id, { line = row, character = range.start.character or 0 }, enc), line_len)
	local end_col
	if range["end"] and range["end"].line == range.start.line then
		end_col =
			math.min(lsp_col_to_byte(buf_id, { line = row, character = range["end"].character or 0 }, enc), line_len)
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
local function preview_symbol(buf_id, item)
	local v = item.value
	if not v.range then
		vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { item.text or "" })
		return
	end
	local lnum = v.range.start.line
	local n_ctx = preview_n_context()
	local lines, hl_row, ft

	if v.filename and (not v.buf or vim.api.nvim_buf_get_name(v.buf) ~= v.filename) then
		-- Cross-file (workspace picker): bounded read around the target line.
		local title = preview_title(v)
		if is_file_text(v.filename) == false then
			vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { title, "-Non-text-file-" })
			return
		end
		local ok_read, file_lines = pcall(vim.fn.readfile, v.filename, "", lnum + 1 + n_ctx)
		if not ok_read or type(file_lines) ~= "table" then
			vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { title, "-No-access-" })
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
		vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { preview_title(v) })
		return
	end
	table.insert(lines, 1, preview_title(v))
	hl_row = math.max(1, math.min(hl_row, #lines - 1))

	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
	if preview_should_highlight(buf_id) then
		highlight_preview(buf_id, ft)
	end
	vim.api.nvim_buf_clear_namespace(buf_id, preview_ns, 0, -1)
	hl.eol(buf_id, preview_ns, 0, 0, "MiniPickHeader", { priority = 200 })
	hl.eol(buf_id, preview_ns, hl_row, 0, "MiniPickPreviewLine", { priority = 201 })
	local col_start, col_end = preview_region_cols(buf_id, hl_row, v.range, v.offset_encoding or "utf-16")
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

M.pick = pick
M.lsp_icon_data = lsp_icon_data
M.notify = notify
M.pick_float_width = pick_float_width
M.symbol_window_config = symbol_window_config
M.apply_symbol_decorations = apply_symbol_decorations
M.symbol_show = symbol_show
M.choose_symbol = choose_symbol
M.choose_symbols_marked = choose_symbols_marked
M.preview_symbol = preview_symbol

return M
