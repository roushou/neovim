--- LSP symbol pickers built on mini.pick.
---
--- - M.doc_symbols()       <leader>ss — textDocument/documentSymbol (tree)
--- - M.workspace_symbols() <leader>sw — workspace/symbol (live search)
---
--- workspace/symbol is async: each (debounced) query change fires a request
--- at every capable client; responses are merged (per-client offset encoding),
--- re-filtered against the current query via set_picker_items, and rendered
--- with a dimmed container name + right-aligned file:line. Stale responses are
--- dropped by query tick. Jump columns are converted from the client's offset
--- encoding to bytes.
---
--- document/symbol renders as a tree: guide rail, kind-colored icons, dot-
--- joined parent chain, dimmed detail and right-aligned kind label. Item text
--- stays decoration-free (no icons/guides) so fuzzy matching ignores them.

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
				vim.api.nvim_buf_set_extmark(buf_id, icon_ns, i - 1, col, {
					hl_group = v.icon_hl,
					end_col = col + #v.icon_text,
					priority = 160,
				})
			end
			if v.guide and #v.guide > 0 then
				vim.api.nvim_buf_set_extmark(buf_id, dim_ns, i - 1, 0, {
					end_col = #v.guide,
					hl_group = "Comment",
					priority = 150,
				})
			end
			if v.dim_col then
				vim.api.nvim_buf_set_extmark(buf_id, dim_ns, i - 1, v.dim_col, {
					hl_eol = true,
					hl_group = "Comment",
					priority = 150,
				})
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
	local width = win ~= -1 and vim.api.nvim_win_get_width(win) or pick_float_width()
	local rendered = {}
	for i, item in ipairs(items) do
		rendered[i] = item.text
		item.text = doc_render(item, width)
	end
	require("mini.pick").default_show(buf_id, items, query, opts)
	for i, item in ipairs(items) do
		item.text = rendered[i]
	end
	apply_symbol_decorations(buf_id, items)
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
		local icon, hl = lsp_icon_data(s.kind)
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
	vim.api.nvim_buf_set_extmark(buf_id, preview_ns, 0, 0, {
		end_row = 0,
		end_col = 0,
		hl_eol = true,
		hl_group = "MiniPickHeader",
		priority = 200,
	})
	vim.api.nvim_buf_set_extmark(buf_id, preview_ns, hl_row, 0, {
		end_row = hl_row,
		end_col = 0,
		hl_eol = true,
		hl_group = "MiniPickPreviewLine",
		priority = 201,
	})
	local col_start, col_end = preview_region_cols(buf_id, hl_row, v.range, v.offset_encoding or "utf-16")
	if col_start then
		vim.api.nvim_buf_set_extmark(buf_id, preview_ns, hl_row, col_start, {
			end_row = hl_row,
			end_col = col_end,
			hl_group = "MiniPickPreviewRegion",
			priority = 202,
		})
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
		notify("No document symbols", vim.log.levels.WARN)
		return
	end

	pick().start({
		source = {
			items = items,
			name = "LSP symbols",
			show = doc_show,
			preview = preview_symbol,
			choose = choose_symbol,
			choose_marked = choose_symbols_marked,
		},
		window = {
			config = symbol_window_config(),
			prompt_prefix = "Symbols: ",
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
	return pick_float_width()
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
			range = {
				start = { line = start.line, character = start.character },
				["end"] = loc.range["end"],
			},
			filename = filename,
			offset_encoding = enc,
			icon_text = icon,
			icon_hl = hl,
			icon_col = 0,
			name = name,
			container = si.containerName,
			kind_label = vim.lsp.protocol.SymbolKind[si.kind] or "",
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
			choose_marked = choose_symbols_marked,
			match = ws_match,
		},
		window = {
			config = symbol_window_config(),
			prompt_prefix = "Workspace: ",
		},
	})
end

map("n", "<leader>ss", M.doc_symbols, { desc = "LSP symbols" })
map("n", "<leader>sw", M.workspace_symbols, { desc = "LSP workspace symbols" })

-- Keep the symbol preview open: mini.pick forces the main view on every
-- match update (typing, items set), so re-toggle to the preview view after
-- each burst. The Tab feed is debounced — queued toggles would cancel out.
-- There is no public view-state API; detect the main view by comparing the
-- main window's buffer against the picker's items buffer.
local preview_timer = vim.uv.new_timer()
vim.api.nvim_create_autocmd("User", {
	pattern = "MiniPickMatch",
	callback = function()
		local name = pick().is_picker_active() and pick().get_picker_opts().source.name
		if not (name == "LSP symbols" or name == "Workspace symbols") then
			return
		end
		local state = pick().get_picker_state()
		if vim.api.nvim_win_get_buf(state.windows.main) == state.buffers.main then
			preview_timer:stop()
			preview_timer:start(
				120,
				0,
				vim.schedule_wrap(function()
					vim.api.nvim_feedkeys(vim.keycode("<Tab>"), "t", false)
				end)
			)
		end
	end,
})

return M
