--- nvim backend: sources served from Neovim's own state, no external tool.
---
--- Always available (`exe` is nil). Candidates carry `bufnr` so the session can
--- reuse the loaded buffer instead of re-reading the file from disk.

local parse = require("loupe.backend.parse")

local M = {} -- no exe: always available

M.list = {
	buffers = function(root, cb)
		local out = {}
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			local name = vim.api.nvim_buf_get_name(buf)
			if vim.bo[buf].buflisted and name ~= "" then
				local rel = parse.relpath(root, name)
				out[#out + 1] = { rel = rel, abs = name, label = rel, bufnr = buf, dir = false }
			end
		end
		cb(out, true)
	end,
}

return M
