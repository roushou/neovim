--- LSP loader: shared defaults + auto-enable of every server in lsp/*.lua.
--- Each lsp/<name>.lua returns a plain config table (pure data); set
--- `enabled = false` in a file to keep it loaded but not activated.

-- merged under every server's own config (files can still override)
vim.lsp.config("*", {
	capabilities = require("blink.cmp").get_lsp_capabilities(),
})

local lsp_dir = vim.fn.stdpath("config") .. "/lsp"

for _, f in ipairs(vim.fn.readdir(lsp_dir)) do
	if f:sub(-4) == ".lua" then
		local name = f:sub(1, -5)
		local ok, cfg = pcall(dofile, lsp_dir .. "/" .. f)
		if not ok then
			vim.notify(("lsp/%s.lua failed to load: %s"):format(name, cfg), vim.log.levels.ERROR)
		else
			vim.lsp.config(name, cfg)
			if cfg.enabled ~= false then
				vim.lsp.enable(name)
			end
		end
	end
end
