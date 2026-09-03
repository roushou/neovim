--- Document-symbol picker (textDocument/documentSymbol), rendered as a tree:
--- guide rail, kind-colored icons, dot-joined parent chain, dimmed detail and
--- right-aligned kind label.

local shared = require("lsp.features.pick.shared")

local M = {}

--- Build a doc-picker item from its parts. `text` is the matchable string
--- (name + container + detail + kind, no icon/guides); the rendered line is
--- composed at show time by doc_render.
local function doc_item(value)
	local v = value
	local guide = v.guide or ""
	local icon = v.icon_text or "•"
	v.icon_col = #guide
	v.dim_col = #(guide .. icon .. " " .. v.name)
	local body = v.name
	if v.container and v.container ~= "" then
		body = body .. " (" .. v.container .. ")"
	end
	if v.detail then
		body = body .. "  " .. v.detail
	end
	v.body = body
	local kind = v.kind_label or ""
	return {
		text = kind ~= "" and (body .. "  " .. kind) or body,
		value = v,
	}
end

--- Compose the rendered line for a doc item: guide rail + icon + clean body,
--- padded so the kind label sits at the window's right edge.
local function doc_render(item, width)
	local v = item.value
	local icon = v.icon_text or "•"
	local kind = v.kind_label or ""
	local pad =
		math.max(1, width - vim.fn.strdisplaywidth(v.guide .. icon .. " " .. v.body) - vim.fn.strdisplaywidth(kind) - 1)
	return v.guide .. icon .. " " .. v.body .. string.rep(" ", pad) .. " " .. kind
end

--- mini.pick render wrapper for the doc picker. Stritems were computed from
--- `text` (clean) when items were set, so matching never sees icons/guides;
--- for display the guide rail + icon are prepended so default_show places
--- match ranges at full-line offsets (swapped back right after).
local function doc_show(buf_id, items, query, opts)
	local win = vim.fn.bufwinid(buf_id)
	local width = win ~= -1 and vim.api.nvim_win_get_width(win) or shared.pick_float_width()
	local rendered = {}
	for i, item in ipairs(items) do
		rendered[i] = item.text
		item.text = doc_render(item, width)
	end
	require("mini.pick").default_show(buf_id, items, query, opts)
	for i, item in ipairs(items) do
		item.text = rendered[i]
	end
	shared.apply_symbol_decorations(buf_id, items)
end

--- Flatten a DocumentSymbol[] tree into picker items with a tree-guide rail,
--- dot-joined parent chain (container), detail and a right-aligned kind label.
--- @param symbols table[] DocumentSymbol[]
--- @param prefix string guide rail inherited from ancestors
--- @param container string dot-joined ancestor names
--- @param items table[] picker items (accumulator)
--- @param enc string offset encoding
local function flatten_doc_symbols(symbols, prefix, container, items, enc)
	for i, s in ipairs(symbols) do
		local is_last = i == #symbols
		local guide = prefix .. (is_last and "└─ " or "├─ ")
		local parent = container == "" and s.name or container .. "." .. s.name
		local detail = (s.detail and s.detail ~= "") and s.detail or nil
		local icon, hl = shared.lsp_icon_data(s.kind)
		items[#items + 1] = doc_item({
			range = s.selectionRange or s.range,
			offset_encoding = enc,
			icon_text = icon,
			icon_hl = hl,
			guide = guide,
			name = s.name,
			container = container,
			detail = detail,
			kind_label = vim.lsp.protocol.SymbolKind[s.kind] or "",
		})
		if s.children then
			flatten_doc_symbols(s.children, prefix .. (is_last and "  " or "│ "), parent, items, enc)
		end
	end
	return items
end

--- Buffer-local symbol picker. Merges responses from every client, keeping
--- each client's offset encoding.
function M.doc_symbols()
	local buf = vim.api.nvim_get_current_buf()
	local ok, res = pcall(vim.lsp.buf_request_sync, 0, "textDocument/documentSymbol", {
		textDocument = vim.lsp.util.make_text_document_params(),
	}, 1000)
	if not ok or not res then
		shared.notify("No document symbols (request timed out)", vim.log.levels.WARN)
		return
	end

	local items = {}
	for _, client_res in ipairs(res) do
		if client_res.err then
			shared.notify(("documentSymbol failed: %s"):format(vim.inspect(client_res.err)), vim.log.levels.WARN)
		elseif client_res.result and not vim.tbl_isempty(client_res.result) then
			local enc = "utf-16"
			local client = vim.lsp.get_client_by_id(client_res.client_id)
			if client then
				enc = client.offset_encoding
			end
			local result = client_res.result
			if result[1].location then
				-- Flat SymbolInformation[] (may point at other files).
				for _, si in ipairs(result) do
					local loc = si.location
					if loc and loc.range then
						local r = loc.range.start
						local icon, hl = shared.lsp_icon_data(si.kind)
						items[#items + 1] = doc_item({
							range = { start = { line = r.line, character = r.character } },
							filename = vim.uri_to_fname(loc.uri),
							offset_encoding = enc,
							icon_text = icon,
							icon_hl = hl,
							guide = "",
							name = si.name,
							container = si.containerName or "",
							detail = nil,
							kind_label = vim.lsp.protocol.SymbolKind[si.kind] or "",
						})
					end
				end
			else
				local flat = flatten_doc_symbols(result, "", "", {}, enc)
				for _, item in ipairs(flat) do
					item.value.buf = buf
				end
				vim.list_extend(items, flat)
			end
		end
	end
	if #items == 0 then
		shared.notify("No document symbols", vim.log.levels.WARN)
		return
	end

	shared.pick().start({
		source = {
			items = items,
			name = "LSP symbols",
			show = doc_show,
			preview = shared.preview_symbol,
			choose = shared.choose_symbol,
			choose_marked = shared.choose_symbols_marked,
		},
		window = {
			config = shared.symbol_window_config(),
			prompt_prefix = "Symbols: ",
		},
	})
end

return M
