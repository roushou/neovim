--- Theme color + highlight helpers.
---
--- Resolves colors from the active colorscheme (following link chains) with
--- fallbacks, and re-applies derived highlight groups on every |ColorScheme|
--- via a single shared autocmd instead of one per consumer.

local M = {}

local refreshers = {}

local function refresh()
	for _, fn in ipairs(refreshers) do
		fn()
	end
end

--- Register a function that (re)derives highlight groups from the active
--- colorscheme. Runs immediately and again on every |ColorScheme|.
function M.on_colorscheme(fn)
	refreshers[#refreshers + 1] = fn
	fn()
end

--- Resolved fg of the first group in `names` (string or list) that has one,
--- or `fallback`.
function M.fg(names, fallback)
	if type(names) == "string" then
		names = { names }
	end
	for _, name in ipairs(names) do
		local hl = vim.api.nvim_get_hl(0, { name = name, link = true, create = false })
		if hl.fg then
			return hl.fg
		end
	end
	return fallback
end

--- Resolved bg of the first group in `names` (string or list) that has one,
--- or `fallback`.
function M.bg(names, fallback)
	if type(names) == "string" then
		names = { names }
	end
	for _, name in ipairs(names) do
		local hl = vim.api.nvim_get_hl(0, { name = name, link = true, create = false })
		if hl.bg then
			return hl.bg
		end
	end
	return fallback
end

vim.api.nvim_create_autocmd("ColorScheme", { callback = refresh })

return M
