--- svelteserver configuration for |vim.lsp.config()|.
return {
	cmd = { "svelteserver", "--stdio" },
	filetypes = { "svelte" },
	root_markers = { "package.json", ".git" },
}
