--- Shared machinery for the LSP symbol pickers.
---
--- Thin facade over the render, nav and preview helpers so the picker modules
--- (`doc`, `workspace`, `init`) have a single require.

local render = require("lsp.features.pick.render")
local nav = require("lsp.features.pick.nav")
local preview = require("lsp.features.pick.preview")

local M = {}

function M.pick()
	return require("mini.pick")
end

function M.notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO)
end

M.lsp_icon_data = render.lsp_icon_data
M.pick_float_width = render.pick_float_width
M.symbol_window_config = render.symbol_window_config
M.apply_symbol_decorations = render.apply_symbol_decorations
M.symbol_show = render.symbol_show
M.choose_symbol = nav.choose_symbol
M.choose_symbols_marked = nav.choose_symbols_marked
M.preview_symbol = preview.preview_symbol

return M
