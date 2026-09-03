require("settings")
require("keymaps")

local gh = function(repo)
	return "https://github.com/" .. repo
end

vim.pack.add({
	-- Colorscheme
	{ src = gh("rebelot/kanagawa.nvim"), name = "kanagawa" },

	-- Mini plugins
	{ src = gh("echasnovski/mini.nvim"), name = "mini.nvim", version = vim.version.range("*") },

	-- Completion
	{
		src = gh("saghen/blink.cmp"),
		name = "blink.cmp",
		version = vim.version.range("1"),
	},
	{ src = gh("rafamadriz/friendly-snippets"), name = "friendly-snippets" },
	{ src = gh("xzbdmw/colorful-menu.nvim"), name = "colorful-menu.nvim" },

	-- Rust
	{
		src = gh("mrcjkb/rustaceanvim"),
		name = "rustaceanvim",
		version = vim.version.range("6"),
	},

	-- Diagnostics
	{ src = gh("folke/trouble.nvim"), name = "trouble.nvim" },

	-- Treesitter
	{ src = gh("nvim-treesitter/nvim-treesitter"), name = "nvim-treesitter" },
	{ src = gh("nvim-treesitter/nvim-treesitter-textobjects"), name = "nvim-treesitter-textobjects" },
	{ src = gh("nvim-treesitter/nvim-treesitter-context"), name = "nvim-treesitter-context" },

	-- UI
	{ src = gh("nvim-neo-tree/neo-tree.nvim"), name = "neo-tree.nvim", version = "v3.x" },
	{ src = gh("nvim-lua/plenary.nvim"), name = "plenary.nvim" },
	{ src = gh("MunifTanjim/nui.nvim"), name = "nui.nvim" },

	-- Git
	{ src = gh("lewis6991/gitsigns.nvim"), name = "gitsigns.nvim" },
	{ src = gh("sindrets/diffview.nvim"), name = "diffview.nvim" },
	{ src = gh("kdheepak/lazygit.nvim"), name = "lazygit.nvim" },

	-- Search & replace
	{ src = gh("nvim-pack/nvim-spectre"), name = "nvim-spectre" },

	-- Indent guides
	{ src = gh("lukas-reineke/indent-blankline.nvim"), name = "indent-blankline.nvim" },

	-- Swift
	{ src = gh("keith/swift.vim"), name = "swift.vim" },

	-- Go
	{ src = gh("ray-x/go.nvim"), name = "go.nvim" },
	{ src = gh("ray-x/guihua.lua"), name = "guihua.lua" },
})

require("lsp")

-- keyd: keymap-reveal plugin (own code)
require("keyd")

-- Custom buffer tabline (own bufferline.nvim replacement)
require("tabline")

-- own formatter runner (conform.nvim replacement)
require("format").attach()

-- Treesitter (setup + textobject keymaps live in lua/plugins/treesitter.lua)
require("plugins.treesitter").setup()

-- Colorscheme (must come after treesitter setup for highlight group linking)
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
