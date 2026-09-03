--- Diagnostic float behavior.
---
--- `[d` / `]d` (vim.diagnostic.jump) shows a float with the diagnostic text
--- and keeps it open until the cursor actually moves. Nvim's default
--- close_events would close it instantly, because a spurious same-position
--- CursorMoved fires when the float opens in this config.

-- Show the float on jump, but disable nvim's default close_events — the
-- CursorMoved handler below owns closing.
vim.diagnostic.config({
	float = { close_events = {} },
	jump = { float = true },
})

-- Close on real cursor movement, ignoring the spurious same-position
-- CursorMoved emitted on the float's opening redraw.
local group = vim.api.nvim_create_augroup("diag_float_close", { clear = true })

local open_float = vim.diagnostic.open_float
---@diagnostic disable-next-line: duplicate-set-field
vim.diagnostic.open_float = function(opts, ...)
	local float_bufnr, winnr = open_float(opts, ...)
	if winnr then
		vim.b[vim.api.nvim_get_current_buf()].diag_float = {
			win = winnr,
			pos = vim.api.nvim_win_get_cursor(0),
		}
	end
	return float_bufnr, winnr
end

vim.api.nvim_create_autocmd("CursorMoved", {
	group = group,
	callback = function()
		local buf = vim.api.nvim_get_current_buf()
		local f = vim.b[buf].diag_float
		if f and vim.api.nvim_win_is_valid(f.win) then
			local pos = vim.api.nvim_win_get_cursor(0)
			if pos[1] ~= f.pos[1] or pos[2] ~= f.pos[2] then
				vim.api.nvim_win_close(f.win, true)
				vim.b[buf].diag_float = nil
			end
		end
	end,
})

return {}
