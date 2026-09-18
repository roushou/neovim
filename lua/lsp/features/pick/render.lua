--- Rendering helpers shared by the LSP symbol pickers.
---
--- Kind icons, float sizing, and the extmarks drawn on top of mini.pick's
--- render (icon, tree-guide rail, dimmed tail).

local hl = require("ui.hl")

local M = {}

-- namespaces for icon + dimmed-tail highlights on top of mini.pick's render
local icon_ns = vim.api.nvim_create_namespace("lsp_pick_icons")
local dim_ns = vim.api.nvim_create_namespace("lsp_pick_dim")

--- LSP kind icon + theme-aware highlight group (MiniIcons* links to theme
--- groups like DiagnosticWarn / Constant / Function, so colors follow the
--- active colorscheme).
function M.lsp_icon_data(kind)
	if not kind then
		return "•", "Comment"
	end
	local icon, icon_hl = require("mini.icons").get("lsp", vim.lsp.protocol.SymbolKind[kind])
	return icon or "•", icon_hl
end

--- Width of symbol-picker floats (0.75 of the screen), shared by both
--- pickers; also the right-alignment target for rendered lines.
function M.pick_float_width()
	return math.floor(0.75 * vim.o.columns)
end

--- Float window config for both pickers: wide and horizontally centered
--- (mini.pick defaults to a bottom-left float).
function M.symbol_window_config()
	local width = M.pick_float_width()
	return {
		width = width,
		col = math.max(0, math.floor((vim.o.columns - width) / 2)),
	}
end

--- Extmarks on top of default_show's render: kind-colored icon, dimmed
--- tree-guide rail (doc picker) and dimmed tail (container/file:line).
--- Priorities sit below MiniPickMatchRanges (200) and MiniPickMatchCurrent.
function M.apply_symbol_decorations(buf_id, items)
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
function M.symbol_show(buf_id, items, query, opts)
	require("mini.pick").default_show(buf_id, items, query, opts)
	M.apply_symbol_decorations(buf_id, items)
end

return M
