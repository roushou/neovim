--- vscode-json-language-server configuration for |vim.lsp.config()|.
return {
	cmd = { "vscode-json-language-server", "--stdio" },
	filetypes = { "json", "jsonc" },
	root_markers = { ".git" },
}
