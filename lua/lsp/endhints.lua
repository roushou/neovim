--- Render LSP inlay hints at the end of the line instead of inline.
---
--- The native textDocument/inlayHint handler places each hint inline at its
--- LSP position; this overrides it to merge all hints of a line into one
--- end-of-line extmark (per line, in column order). Also auto-enables hints
--- for inlayHint-capable clients on attach and keeps the namespace in sync
--- with |vim.lsp.inlay_hint.enable()|.

local M = {}

local ns = vim.api.nvim_create_namespace("lsp_endhints")

local ICONS = {
	type = "󰜁 ",
	parameter = "󰏪 ",
	offspec = " ",
	unknown = " ",
}

local TRUNCATE_AT = 20
local PADDING = 1
local SAME_KIND_SEPARATOR = ", "
local PRIORITY = 50

local original_enable = vim.lsp.inlay_hint.enable

--- InlayHintKind → label group (1=type, 2=parameter).
local function kind_of(hint)
	local kind = hint.kind
	if kind == 1 then
		return "type"
	elseif kind == 2 then
		return "parameter"
	elseif kind == nil then
		return "unknown"
	else
		return "offspec"
	end
end

--- Hint label as string (handles label parts), trimmed and truncated.
local function label_of(hint)
	local label = hint.label
	if type(label) ~= "string" then
		label = vim.iter(label)
			:map(function(part)
				return part.value
			end)
			:join("")
	end
	label = vim.trim(label:gsub("^:", ""):gsub(":$", ""))
	if #label > TRUNCATE_AT then
		label = label:sub(1, TRUNCATE_AT) .. "…"
	end
	return label
end

--- Merge a line's hints (already in column order): icon on kind change,
--- separator between hints of equal kind.
local function merge_hints(hints)
	local parts = {}
	local last_kind
	for _, hint in ipairs(hints) do
		local kind = kind_of(hint)
		local label = label_of(hint)
		if last_kind == kind then
			parts[#parts + 1] = SAME_KIND_SEPARATOR .. label
		else
			local pad = #parts > 0 and " " or ""
			parts[#parts + 1] = pad .. ICONS[kind] .. label
		end
		last_kind = kind
	end
	return table.concat(parts)
end

local function refresh_handler(_, result, ctx)
	local bufnr = ctx.bufnr or -1
	if not vim.api.nvim_buf_is_valid(bufnr) or not result then
		return
	end
	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

	-- group hints by line, preserving order for column sorting
	local by_line = {}
	for _, hint in ipairs(result) do
		local lnum = hint.position.line
		by_line[lnum] = by_line[lnum] or {}
		table.insert(by_line[lnum], hint)
	end

	for lnum, hints in pairs(by_line) do
		table.sort(hints, function(a, b)
			return a.position.character < b.position.character
		end)
		local text = (" "):rep(PADDING) .. merge_hints(hints) .. (" "):rep(PADDING)
		vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, 0, {
			virt_text = { { text, "LspInlayHint" } },
			virt_text_pos = "eol",
			hl_mode = "combine",
			strict = false,
			priority = PRIORITY,
		})
	end
end

vim.lsp.handlers["textDocument/inlayHint"] = refresh_handler

-- Keep the namespace in sync when hints are toggled natively
-- (per-filetype overrides in settings.lua call this).
-- Intentional override of the typed API function: clears the eol extmarks.
---@diagnostic disable-next-line: duplicate-set-field
vim.lsp.inlay_hint.enable = function(enable, filter)
	if enable == false then
		local buffers
		if filter and filter.bufnr then
			buffers = { filter.bufnr }
		else
			buffers = {}
			for _, client in ipairs(vim.lsp.get_clients()) do
				for bufnr in pairs(client.attached_buffers) do
					buffers[#buffers + 1] = bufnr
				end
			end
		end
		for _, bufnr in ipairs(buffers) do
			if vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
			end
		end
	end
	original_enable(enable, filter)
end

-- Auto-enable hints for inlayHint-capable clients (mirrors the plugin's
-- autoEnableHints; per-filetype overrides in settings.lua still apply).
vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach" }, {
	group = vim.api.nvim_create_augroup("lsp_endhints", { clear = true }),
	callback = function(ctx)
		local client = vim.lsp.get_client_by_id(ctx.data.client_id)
		if not client or not client.server_capabilities.inlayHintProvider then
			return
		end
		vim.lsp.inlay_hint.enable(ctx.event == "LspAttach", { bufnr = ctx.buf })
	end,
})

return M
