local M = {}

function M.map(mode, keys, func, opts)
	local options = { noremap = true, silent = true }
	if opts then
		options = vim.tbl_extend("force", options, opts)
	end
	vim.keymap.set(mode, keys, func, options)
end

--- Run `fn(buf)` once per buffer, guarded by the buffer-local flag `key`.
--- Returns true when `fn` ran, false when the buffer was already attached.
function M.attach_once(buf, key, fn)
	buf = buf or 0
	if vim.b[buf][key] then
		return false
	end
	vim.b[buf][key] = true
	fn(buf)
	return true
end

--- Create an autocmd group, clearing any existing group of the same name.
function M.augroup(name)
	return vim.api.nvim_create_augroup(name, { clear = true })
end

return M
