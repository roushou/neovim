--- LSP symbol pickers (own namu.nvim replacement) built on mini.pick.
---
--- - M.doc_symbols()       <leader>ss — textDocument/documentSymbol (tree)
--- - M.workspace_symbols() <Bslash>   — workspace/symbol
---
--- Both route into mini.pick for fuzzy filtering and preview; jumps happen
--- in the picker's target window. LSP positions use the client's offset
--- encoding, so jump columns are converted to bytes for nvim.

local map = require("util").map

local M = {}

-- namespaces for icon + preview-line highlights on top of mini.pick's render
local icon_ns = vim.api.nvim_create_namespace("lsp_pick_icons")
local preview_ns = vim.api.nvim_create_namespace("lsp_pick_preview")

local function pick()
	return require("mini.pick")
end

--- LSP kind icon + theme-aware highlight group (MiniIcons* links to theme
--- groups like DiagnosticWarn / Constant / Function, so colors follow the
--- active colorscheme).
local function lsp_icon_data(kind)
	local icon, hl = require("mini.icons").get("lsp", vim.lsp.protocol.SymbolKind[kind])
	return icon or "•", hl
end

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO)
end

--- Offset encoding of the first client attached to a buffer.
local function offset_encoding(buf)
	local client = vim.lsp.get_clients({ bufnr = buf })[1]
	return client and client.offset_encoding or "utf-16"
end

--- mini.pick render wrapper: default rendering + per-kind icon highlights
--- (MiniIcons* groups) so the symbols respect the colorscheme.
local function symbol_show(buf_id, items, query, opts)
	require("mini.pick").default_show(buf_id, items, query, opts)
	vim.api.nvim_buf_clear_namespace(buf_id, icon_ns, 0, -1)
	for i, item in ipairs(items) do
		local v = item.value
		if v and v.icon_hl and v.icon_text then
			local col = v.icon_col or 0
			vim.api.nvim_buf_set_extmark(buf_id, icon_ns, i - 1, col, {
				hl_group = v.icon_hl,
				end_col = col + #v.icon_text,
			})
		end
	end
end

--- Flatten a DocumentSymbol[] tree into picker items with depth indentation.
--- @param symbols table[] DocumentSymbol[]
--- @param depth integer
--- @param items table[] picker items (accumulator)
--- @param enc string offset encoding
local function flatten_doc_symbols(symbols, depth, items, enc)
	for _, s in ipairs(symbols) do
		local icon, hl = lsp_icon_data(s.kind)
		local text = string.rep("  ", depth) .. icon .. " " .. s.name
		if s.detail and s.detail ~= "" then
			text = text .. "  " .. s.detail
		end
		items[#items + 1] = {
			text = text,
			value = {
				range = s.selectionRange or s.range,
				offset_encoding = enc,
				icon_text = icon,
				icon_hl = hl,
				icon_col = 2 * depth,
			},
		}
		if s.children then
			flatten_doc_symbols(s.children, depth + 1, items, enc)
		end
	end
	return items
end

--- Shared choose: jump to item.value.range.start (editing the file first when
--- it differs from the buffer in the target window).
local function choose_symbol(item)
	local v = item.value
	local win = pick().get_picker_state().windows.target
	vim.api.nvim_win_call(win, function()
		if v.filename and vim.api.nvim_buf_get_name(0) ~= v.filename then
			vim.cmd("edit " .. vim.fn.fnameescape(v.filename))
		end
		local pos = v.range.start
		local col = vim.lsp.util._get_line_byte_from_position(0, pos, v.offset_encoding or "utf-16")
		vim.api.nvim_win_set_cursor(0, { pos.line + 1, col })
	end)
end

--- Theme-aware highlighting for a preview scratch buffer: treesitter when a
--- parser exists, otherwise native Vim syntax (colors come from the active
--- colorscheme either way; mirrors mini.pick's preview_set_lines).
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

--- Shared preview: fill the scratch buffer with lines around the symbol, apply
--- theme-aware syntax colors and highlight the target line.
local function preview_symbol(buf_id, item)
	local v = item.value
	local lines, hl_line, ft
	if v.filename and (not v.buf or vim.api.nvim_buf_get_name(v.buf) ~= v.filename) then
		lines = vim.fn.readfile(v.filename) or {}
		hl_line = v.range.start.line
		ft = vim.filetype.match({ filename = v.filename })
	else
		local buf = v.buf or vim.api.nvim_get_current_buf()
		lines = vim.api.nvim_buf_get_lines(buf, v.range.start.line, v.range.start.line + 8, false)
		hl_line = 0
		ft = vim.bo[buf].filetype
	end
	vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
	if preview_should_highlight(buf_id) then
		highlight_preview(buf_id, ft)
	end
	vim.api.nvim_buf_clear_namespace(buf_id, preview_ns, 0, -1)
	vim.api.nvim_buf_set_extmark(buf_id, preview_ns, hl_line, 0, {
		end_row = hl_line,
		end_col = 0,
		hl_eol = true,
		hl_group = "MiniPickPreviewLine",
		priority = 201, -- above syntax (50) and treesitter (100)
	})
end

--- Buffer-local symbol picker (textDocument/documentSymbol).
function M.doc_symbols()
	local buf = vim.api.nvim_get_current_buf()
	local enc = offset_encoding(buf)
	local ok, res = pcall(vim.lsp.buf_request_sync, 0, "textDocument/documentSymbol", {
		textDocument = vim.lsp.util.make_text_document_params(),
	}, 1000)
	if not ok or not res or not res[1] or not res[1].result or vim.tbl_isempty(res[1].result) then
		notify("No document symbols", vim.log.levels.WARN)
		return
	end
	local result = res[1].result

	local items
	if result[1].location then
		-- Flat SymbolInformation[] (may point at other files).
		items = {}
		for _, si in ipairs(result) do
			local r = si.location.range.start
			local icon, hl = lsp_icon_data(si.kind)
			items[#items + 1] = {
				text = icon .. " " .. si.name,
				value = {
					range = { start = { line = r.line, character = r.character } },
					filename = vim.uri_to_fname(si.location.uri),
					offset_encoding = enc,
					icon_text = icon,
					icon_hl = hl,
					icon_col = 0,
				},
			}
		end
	else
		items = flatten_doc_symbols(result, 0, {}, enc)
		for _, item in ipairs(items) do
			item.value.buf = buf
		end
	end

	pick().start({
		source = {
			items = items,
			name = "LSP symbols",
			show = symbol_show,
			preview = preview_symbol,
			choose = choose_symbol,
		},
	})
end

--- Workspace-wide symbol picker (workspace/symbol).
function M.workspace_symbols()
	local buf = vim.api.nvim_get_current_buf()
	local enc = offset_encoding(buf)
	local query = vim.fn.input("Symbol query: ")
	if query == "" then
		return
	end
	local ok, res = pcall(vim.lsp.buf_request_sync, 0, "workspace/symbol", { query = query }, 2000)
	if not ok or not res or not res[1] or not res[1].result or vim.tbl_isempty(res[1].result) then
		notify("No workspace symbols", vim.log.levels.WARN)
		return
	end

	local items = {}
	for _, si in ipairs(res[1].result) do
		if si.location then
			local r = si.location.range.start
			local icon, hl = lsp_icon_data(si.kind)
			items[#items + 1] = {
				text = icon .. " " .. si.name,
				value = {
					range = { start = { line = r.line, character = r.character } },
					filename = vim.uri_to_fname(si.location.uri),
					offset_encoding = enc,
					icon_text = icon,
					icon_hl = hl,
					icon_col = 0,
				},
			}
		end
	end
	if #items == 0 then
		notify("No workspace symbols", vim.log.levels.WARN)
		return
	end

	pick().start({
		source = {
			items = items,
			name = "Workspace symbols",
			show = symbol_show,
			preview = preview_symbol,
			choose = choose_symbol,
		},
	})
end

map("n", "<leader>ss", M.doc_symbols, { desc = "LSP symbols" })
map("n", "<Bslash>", M.workspace_symbols, { desc = "LSP workspace symbols" })

return M
