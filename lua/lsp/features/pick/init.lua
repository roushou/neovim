--- LSP symbol pickers: entry point aggregating the document and workspace
--- pickers, plus the preview-open behavior shared by both.

local shared = require("lsp.features.pick.shared")
local doc = require("lsp.features.pick.doc")
local workspace = require("lsp.features.pick.workspace")

local M = {
	doc_symbols = doc.doc_symbols,
	workspace_symbols = workspace.workspace_symbols,
}

-- Keep the symbol preview open: mini.pick forces the main view on every
-- match update (typing, items set), so re-toggle to the preview view after
-- each burst. The Tab feed is debounced — queued toggles would cancel out.
-- There is no public view-state API; detect the main view by comparing the
-- main window's buffer against the picker's items buffer.
local preview_timer = vim.uv.new_timer()
vim.api.nvim_create_autocmd("User", {
	pattern = "MiniPickMatch",
	callback = function()
		local name = shared.pick().is_picker_active() and shared.pick().get_picker_opts().source.name
		if not (name == "LSP symbols" or name == "Workspace symbols") then
			return
		end
		local state = shared.pick().get_picker_state()
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
