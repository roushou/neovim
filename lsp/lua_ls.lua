--- lua-language-server configuration for |vim.lsp.config()|.
--- Pure data; shared defaults (capabilities) come from lua/lsp/setup.lua.
return {
	cmd = { "lua-language-server" },
	filetypes = { "lua" },
	root_markers = { ".luarc.json", ".luarc.jsonc", ".git" },
	settings = {
		Lua = {
			runtime = { version = "LuaJIT" },
			diagnostics = { globals = { "vim" } },
			completion = { callSnippet = "Replace" },
			telemetry = { enable = false },
			workspace = {
				library = vim.api.nvim_get_runtime_file("", true),
				checkThirdParty = false,
			},
		},
	},
}
