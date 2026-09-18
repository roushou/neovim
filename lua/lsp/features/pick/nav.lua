--- Navigation, choose and quickfix helpers shared by the LSP symbol pickers.

local M = {}

local function pick()
	return require("mini.pick")
end

--- Byte column of an LSP position within a buffer's line (uses the public
--- vim.str_byteindex, not vim.lsp.util private API).
function M.lsp_col_to_byte(buf, pos, enc)
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
function M.choose_symbol(item)
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
		local col = M.lsp_col_to_byte(0, pos, v.offset_encoding or "utf-16")
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
function M.choose_symbols_marked(items_marked)
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

return M
