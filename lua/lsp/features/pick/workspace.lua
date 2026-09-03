--- Workspace-symbol picker (workspace/symbol), a live search: each debounced
--- query change fires a request at every capable client; responses are merged
--- (per-client offset encoding), re-filtered via set_picker_items, and
--- rendered with a dimmed container + right-aligned file:line.

local shared = require("lsp.features.pick.shared")

local M = {}

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
	local state = shared.pick().get_picker_state()
	local win = state and state.windows.main
	if win and vim.api.nvim_win_is_valid(win) then
		return vim.api.nvim_win_get_width(win)
	end
	return shared.pick_float_width()
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
	local icon, hl = shared.lsp_icon_data(si.kind)
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
	shared.notify(msg, vim.log.levels.WARN)
	ws.acc, ws.loading = nil, false
	if shared.pick().is_picker_active() and shared.pick().get_querytick() == tick then
		shared.pick().set_picker_items({ ws_placeholder(msg) }, { querytick = tick, do_match = false })
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
	if not shared.pick().is_picker_active() or shared.pick().get_querytick() ~= tick then
		return
	end
	if #acc.items == 0 and err_msg then
		ws_show_error(err_msg, tick)
	elseif #acc.items == 0 then
		shared.pick().set_picker_items({}, { querytick = tick }) -- no matches
	else
		shared.pick().set_picker_items(acc.items, { querytick = tick })
	end
end

--- Fire workspace/symbol at every capable client; merge responses.
local function ws_request(q, tick)
	if not shared.pick().is_picker_active() or shared.pick().get_querytick() ~= tick then
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
			if shared.pick().is_picker_active() then
				shared.pick().set_picker_items({ ws_placeholder("Type to search workspace symbols…") }, {
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
	ws_on_query(q, shared.pick().get_querytick())
	inds = require("mini.pick").default_match(stritems, inds, query, { sync = true })
	if #inds == 0 and #stritems > 0 and ws.loading then
		inds = { 1 } -- placeholder stays until results arrive
	end
	return inds
end

--- Workspace-wide symbol picker: opens immediately and queries capable
--- clients on each query change (see module doc).
function M.workspace_symbols()
	local buf = vim.api.nvim_get_current_buf()
	local capable = vim.tbl_filter(function(c)
		return c:supports_method("workspace/symbol", buf)
	end, vim.lsp.get_clients({ bufnr = buf }))
	if #capable == 0 then
		shared.notify("No client supports workspace/symbol", vim.log.levels.WARN)
		return
	end

	ws_reset()
	ws.buf = buf
	shared.pick().start({
		source = {
			items = { ws_placeholder("Type to search workspace symbols…") },
			name = "Workspace symbols",
			show = shared.symbol_show,
			preview = shared.preview_symbol,
			choose = shared.choose_symbol,
			choose_marked = shared.choose_symbols_marked,
			match = ws_match,
		},
		window = {
			config = shared.symbol_window_config(),
			prompt_prefix = "Workspace: ",
		},
	})
end

return M
