--- tombi (toml) configuration for |vim.lsp.config()|.
return {
	cmd = { "tombi", "lsp" },
	filetypes = { "toml" },
	root_markers = { "tombi.toml", "pyproject.toml", ".git" },
}
