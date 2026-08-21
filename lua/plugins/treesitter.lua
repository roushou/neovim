local M = {}

-- Parsers to ensure are always installed.
-- Call `:TSUpdate` to update them, `:TSInstall {lang}` to add new ones.
-- html/js/ts/svelte/vue power the native tag helpers (after/plugin/tagged.lua).
M.ensure_installed = {
	"lua",
	"vimdoc",
	"rust",
	"go",
	"python",
	"odin",
	"html",
	"javascript",
	"typescript",
	"tsx",
	"svelte",
	"vue",
}

-- Filetypes for which treesitter highlighting + indentation will be enabled.
-- These should match parser names (e.g. vimdoc → help filetype).
M.filetypes = { "lua", "help", "rust", "go", "python", "svelte", "typescript", "odin" }

-- Configuration for nvim-treesitter-textobjects.
M.textobjects = {
	select = {
		lookahead = true,
	},
	move = {
		set_jumps = true,
	},
}

return M
