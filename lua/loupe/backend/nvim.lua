--- nvim backend: sources served from Neovim's own state, no external tool.
---
--- Always available (`exe` is nil). Buffer candidates carry `bufnr` so the
--- session can reuse the loaded buffer instead of re-reading from disk.

local parse = require("loupe.backend.parse")

local M = {} -- no exe: always available

M.list = {
	buffers = function(ctx, cb)
		local out = {}
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			local name = vim.api.nvim_buf_get_name(buf)
			if vim.bo[buf].buflisted and name ~= "" then
				local rel = parse.relpath(ctx.root, name)
				out[#out + 1] = { rel = rel, abs = name, label = rel, bufnr = buf, dir = false }
			end
		end
		cb(out, true)
	end,

	diagnostics = function(ctx, cb)
		local out = {}
		for _, d in ipairs(vim.diagnostic.get()) do
			local name = d.bufnr and vim.api.nvim_buf_is_valid(d.bufnr) and vim.api.nvim_buf_get_name(d.bufnr) or ""
			if name ~= "" then
				local rel = parse.relpath(ctx.root, name)
				local lnum = d.lnum + 1
				out[#out + 1] = {
					rel = rel,
					abs = name,
					label = rel .. ":" .. lnum .. ": " .. (d.message or ""),
					lnum = lnum,
					col = d.col or 0,
					severity = d.severity,
					dir = false,
				}
			end
		end
		cb(out, true)
	end,
}

return M
