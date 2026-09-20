--- Jump to a candidate's file and position, reusing an already-loaded buffer.
---
--- Used as the `choose` hook for location sources (symbols, diagnostics): unlike
--- the default open, it does not `:edit` (which would reload the file and lose
--- unsaved changes) — it switches to the existing buffer and centers the target
--- line.

local M = {}

--- @param cand loupe.Candidate
--- @param kind "edit"|"split"|"vsplit"|"tab"
--- @param ctx table  session context with `close`
--- @return boolean false  (the picker closes)
function M.choose(cand, kind, ctx)
	ctx.close()
	if kind == "split" then
		vim.cmd("split")
	elseif kind == "vsplit" then
		vim.cmd("vsplit")
	elseif kind == "tab" then
		vim.cmd("tabnew")
	end

	local buf = vim.fn.bufadd(cand.abs)
	vim.bo[buf].buflisted = true
	vim.api.nvim_win_set_buf(0, buf)

	local lnum = math.max(1, cand.lnum or 1)
	local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
	vim.api.nvim_win_set_cursor(0, { lnum, math.max(0, math.min(cand.col or 0, #line)) })
	vim.cmd("normal! zvzz")
	return false
end

return M
