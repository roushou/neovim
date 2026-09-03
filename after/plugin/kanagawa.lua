-- Loads after treesitter setup (lua/plugins/treesitter.lua), which kanagawa
-- needs for highlight-group linking.
require("kanagawa").setup({
	colors = {
		theme = {
			all = {
				ui = {
					bg_gutter = "none",
				},
			},
		},
	},
})
vim.cmd.colorscheme("kanagawa")
