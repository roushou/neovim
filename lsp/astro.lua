--- astro language server configuration for |vim.lsp.config()|.
return {
	cmd = { "astro-ls", "--stdio" },
	filetypes = { "astro" },
	root_markers = { "package.json", "tsconfig.json", "jsconfig.json", ".git" },
}
