--- vscode-css-language-server configuration for |vim.lsp.config()|.
return {
	cmd = { "vscode-css-language-server", "--stdio" },
	filetypes = { "css", "scss", "less" },
	root_markers = { "package.json", ".git" },
}
