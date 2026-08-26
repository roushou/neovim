--- LSP symbol pickers built on mini.pick.
---
--- - M.doc_symbols()       <leader>ss — textDocument/documentSymbol (tree)
--- - M.workspace_symbols() <Bslash>   — workspace/symbol (live search)
---
--- workspace/symbol is async: each (debounced) query change fires a request
--- at every capable client; responses are merged (per-client offset encoding),
--- re-filtered against the current query via set_picker_items, and rendered
--- with a dimmed container name + right-aligned file:line. Stale responses are
--- dropped by query tick. Jump columns are converted from the client's offset
--- encoding to bytes.

local map = require("util").map

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

--- mini.pick render wrapper: default rendering + per-kind icon highlights
--- (MiniIcons* groups) and a dimmed tail (container + file:line) for workspace
--- results.
local function symbol_show(buf_id, items, query, opts)
	require("mini.pick").default_show(buf_id, items, query, opts)
	vim.api.nvim_buf_clear_namespace(buf_id, icon_ns, 0, -1)
	vim.api.nvim_buf_clear_namespace(buf_id, dim_ns, 0, -1)
	for i, item in ipairs(items) do
		local v = item.value
		if v then
			if v.icon_hl and v.icon_text then
				local col = v.icon_col or 0
				vim.api.nvim_buf_set_extmark(buf_id, icon_ns, i - 1, col, {
					hl_group = v.icon_hl,
					end_col = col + #v.icon_text,
				})
			end
			if v.dim_col then
				vim.api.nvim_buf_set_extmark(buf_id, dim_ns, i - 1, v.dim_col, {
					hl_eol = true,
					hl_group = "Comment",
					priority = 150, -- above icons, below match ranges (200)
				})
			end
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
	if not v.range then
		return true -- placeholder (search hint / error message): keep picker open
	end
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

--- Shared preview: fill the scratch buffer with lines around the symbol, apply
--- theme-aware syntax colors and highlight the target line.
local function preview_symbol(buf_id, item)
	local v = item.value
	if not v.range then
		vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, { item.text or "" })
		return
	end
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

--- Buffer-local symbol picker (textDocument/documentSymbol). Merges responses
--- from every client, keeping each client's offset encoding.
function M.doc_symbols()
	local buf = vim.api.nvim_get_current_buf()
	local ok, res = pcall(vim.lsp.buf_request_sync, 0, "textDocument/documentSymbol", {
		textDocument = vim.lsp.util.make_text_document_params(),
	}, 1000)
	if not ok or not res then
		notify("No document symbols (request timed out)", vim.log.levels.WARN)
		return
	end

	local items = {}
	for _, client_res in ipairs(res) do
		if client_res.err then
			notify(("documentSymbol failed: %s"):format(vim.inspect(client_res.err)), vim.log.levels.WARN)
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
						local icon, hl = lsp_icon_data(si.kind)
						items[#items + 1] = {
							text = icon .. " " .. si.name,
							value = {
								range = { start = { line = r.line, character = r.character } },
								filename = vim.uri_to_fname(loc.uri),
								offset_encoding = enc,
								icon_text = icon,
								icon_hl = hl,
								icon_col = 0,
							},
						}
					end
				end
			else
				local flat = flatten_doc_symbols(result, 0, {}, enc)
				for _, item in ipairs(flat) do
					item.value.buf = buf
				end
				vim.list_extend(items, flat)
			end
		end
	end
	if #items == 0 then
		notify("No document symbols", vim.log.levels.WARN)
		return
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

-- Workspace picker -----------------------------------------------------------

--- Workspace picker state.
--- - timer: debounce between query changes and server requests.
--- - timeout: safety net for servers that never answer.
--- - acc: accumulator of the in-flight request (one per query tick).
--- - loading: whether a request is pending (keeps the search hint visible).
local ws = {
	buf = nil,
	timer = vim.uv.new_timer(),
	timeout = vim.uv.new_timer(),
	last_q = "",
	last_tick = nil,
	loading = false,
	acc = nil,
}

local function ws_reset()
	ws.timer:stop()
	ws.timeout:stop()
	ws.buf = nil
	ws.last_q = ""
	ws.last_tick = nil
	ws.loading = false
	ws.acc = nil
end

--- Placeholder item (search hint / error message). Never choosable.
local function ws_placeholder(text)
	return { text = text, value = { placeholder = true } }
end

--- Width of the picker's main window, for right-aligning file:line.
local function ws_window_width()
	local state = pick().get_picker_state()
	local win = state and state.windows.main
	if win and vim.api.nvim_win_is_valid(win) then
		return vim.api.nvim_win_get_width(win)
	end
	return math.floor(0.75 * vim.o.columns)
end

--- One workspace/symbol result → picker item: icon + name undimmed, container
--- and right-aligned relative file:line dimmed (see symbol_show).
--- @return table|nil
local function ws_build_item(si, enc)
	local loc = si.location
	if not loc or not loc.range or not loc.range.start or not loc.uri then
		return nil
	end
	local start = loc.range.start
	local icon, hl = lsp_icon_data(si.kind)
	local name = si.name or "?"
	local filename = vim.uri_to_fname(loc.uri)
	local rel = vim.fn.fnamemodify(filename, ":~:.")
	if vim.fn.strchars(rel) > 40 then
		rel = "…" .. vim.fn.strcharpart(rel, vim.fn.strchars(rel) - 38)
	end
	local line_no = start.line + 1

	local left = icon .. " " .. name
	if si.containerName and si.containerName ~= "" then
		left = left .. " (" .. si.containerName .. ")"
	end
	local right = " " .. rel .. ":" .. line_no
	local width = ws_window_width()
	local pad = math.max(1, width - vim.fn.strdisplaywidth(left) - vim.fn.strdisplaywidth(right))
	local text = left .. string.rep(" ", pad) .. right

	return {
		text = text,
		value = {
			range = { start = { line = start.line, character = start.character } },
			filename = filename,
			offset_encoding = enc,
			icon_text = icon,
			icon_hl = hl,
			icon_col = 0,
			name = name,
			container = si.containerName,
			rel = rel,
			line_no = line_no,
			-- byte offset where the dimmed tail begins (after icon + name)
			dim_col = #(icon .. " " .. name),
		},
	}
end

--- Show an error as a notification + non-choosable in-list item.
local function ws_show_error(msg, tick)
	notify(msg, vim.log.levels.WARN)
	ws.acc, ws.loading = nil, false
	if pick().is_picker_active() and pick().get_querytick() == tick then
		pick().set_picker_items({ ws_placeholder(msg) }, { querytick = tick, do_match = false })
	end
end

--- Deliver the accumulator: only the current one may do so. If the query
--- changed meanwhile the results are stale and dropped (a newer request owns
--- the state); err_msg is shown when nothing at all was collected.
local function ws_deliver(acc, tick, err_msg)
	if ws.acc ~= acc then
		return
	end
	ws.timeout:stop()
	ws.acc, ws.loading = nil, false
	if not pick().is_picker_active() or pick().get_querytick() ~= tick then
		return
	end
	if #acc.items == 0 and err_msg then
		ws_show_error(err_msg, tick)
	elseif #acc.items == 0 then
		pick().set_picker_items({}, { querytick = tick }) -- no matches
	else
		pick().set_picker_items(acc.items, { querytick = tick })
	end
end

--- Fire workspace/symbol at every capable client; merge responses.
local function ws_request(q, tick)
	if not pick().is_picker_active() or pick().get_querytick() ~= tick then
		return
	end
	ws.loading = true
	local capable = vim.tbl_filter(function(c)
		return c:supports_method("workspace/symbol", ws.buf)
	end, vim.lsp.get_clients({ bufnr = ws.buf }))
	if #capable == 0 then
		ws_show_error("No client supports workspace/symbol", tick)
		return
	end

	local acc = { tick = tick, n = #capable, done = 0, items = {}, err = nil }
	ws.acc = acc

	-- Safety net: if a server never answers, deliver whatever came back.
	ws.timeout:stop()
	ws.timeout:start(
		5000,
		0,
		vim.schedule_wrap(function()
			if ws.acc ~= acc then
				return
			end
			ws_deliver(acc, tick, #acc.items == 0 and "workspace/symbol timed out" or nil)
		end)
	)

	vim.lsp.buf_request(ws.buf, "workspace/symbol", { query = q }, function(err, result, ctx, _)
		if ws.acc ~= acc then
			return -- superseded by a newer request
		end
		acc.done = acc.done + 1
		if err then
			acc.err = acc.err or err
		else
			local enc = "utf-16"
			local client = vim.lsp.get_client_by_id(ctx.client_id)
			if client then
				enc = client.offset_encoding
			end
			for _, si in ipairs(result or {}) do
				local item = ws_build_item(si, enc)
				if item then
					acc.items[#acc.items + 1] = item
				end
			end
		end
		if acc.done >= acc.n then
			ws_deliver(acc, tick, acc.err and ("workspace/symbol failed: " .. vim.inspect(acc.err)))
		end
	end)
end

--- Query hook: runs inside source.match on every query change and on every
--- items update. Arms the debounced server request for non-empty queries and
--- restores the search hint when the query is cleared.
local function ws_on_query(q, tick)
	if q == "" then
		ws.timer:stop()
		ws.timeout:stop()
		ws.acc, ws.loading = nil, false
		if ws.last_q ~= "" then
			ws.last_q = ""
			if pick().is_picker_active() then
				pick().set_picker_items({ ws_placeholder("Type to search workspace symbols…") }, {
					querytick = tick,
				})
			end
		end
		return
	end
	if q == ws.last_q and tick == ws.last_tick then
		return -- same query already handled (e.g. items just got updated)
	end
	ws.last_q, ws.last_tick = q, tick
	ws.loading = true
	ws.timer:stop()
	ws.timer:start(
		200,
		0,
		vim.schedule_wrap(function()
			ws_request(q, tick)
		end)
	)
end

--- source.match wrapper: default fuzzy matching (synchronous so we can tweak
--- the result) + keep the search-hint placeholder visible while a request is
--- in flight.
local function ws_match(stritems, inds, query)
	local q = table.concat(query)
	ws_on_query(q, pick().get_querytick())
	inds = require("mini.pick").default_match(stritems, inds, query, { sync = true })
	if #inds == 0 and #stritems > 0 and ws.loading then
		inds = { 1 } -- placeholder stays until results arrive
	end
	return inds
end

--- Workspace-wide symbol picker (workspace/symbol): opens immediately and
--- queries capable clients on each query change (see module doc).
function M.workspace_symbols()
	local buf = vim.api.nvim_get_current_buf()
	local capable = vim.tbl_filter(function(c)
		return c:supports_method("workspace/symbol", buf)
	end, vim.lsp.get_clients({ bufnr = buf }))
	if #capable == 0 then
		notify("No client supports workspace/symbol", vim.log.levels.WARN)
		return
	end

	ws_reset()
	ws.buf = buf
	pick().start({
		source = {
			items = { ws_placeholder("Type to search workspace symbols…") },
			name = "Workspace symbols",
			show = symbol_show,
			preview = preview_symbol,
			choose = choose_symbol,
			match = ws_match,
		},
		window = { config = { width = math.floor(0.75 * vim.o.columns) } },
	})
end

map("n", "<leader>ss", M.doc_symbols, { desc = "LSP symbols" })
map("n", "<Bslash>", M.workspace_symbols, { desc = "LSP workspace symbols" })

return M
