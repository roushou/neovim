local map = require("util").map

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
M.filetypes = {
	"lua",
	"help",
	"rust",
	"go",
	"python",
	"svelte",
	"typescript",
	"typescriptreact",
	"javascript",
	"javascriptreact",
	"odin",
}

-- Configuration for nvim-treesitter-textobjects.
M.textobjects = {
	select = {
		lookahead = true,
	},
	move = {
		set_jumps = true,
	},
}

-- Sets up treesitter and all related plugins + keymaps.
-- Must run before the colorscheme so kanagawa can link its highlight groups.
function M.setup()
	require("nvim-treesitter").setup({})
	require("nvim-treesitter").install(M.ensure_installed)

	-- Enable treesitter highlighting + indentation per filetype
	vim.api.nvim_create_autocmd("FileType", {
		pattern = M.filetypes,
		callback = function()
			vim.treesitter.start()
			vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
		end,
	})

	-- Textobjects
	local textobjects = require("nvim-treesitter-textobjects")
	textobjects.setup(M.textobjects)

	-- Select keymaps
	local select_mod = require("nvim-treesitter-textobjects.select")
	map({ "x", "o" }, "af", function()
		select_mod.select_textobject("@function.outer")
	end, { desc = "Select function outer" })
	map({ "x", "o" }, "if", function()
		select_mod.select_textobject("@function.inner")
	end, { desc = "Select function inner" })
	map({ "x", "o" }, "ac", function()
		select_mod.select_textobject("@class.outer")
	end, { desc = "Select class outer" })

	-- Move keymaps
	local move_mod = require("nvim-treesitter-textobjects.move")
	map({ "n", "x", "o" }, "]m", function()
		move_mod.goto_next_start("@function.outer")
	end, { desc = "Next function start" })
	map({ "n", "x", "o" }, "]o", function()
		move_mod.goto_next_start({ "@loop.inner", "@loop.outer" })
	end, { desc = "Next loop" })
	map({ "n", "x", "o" }, "]s", function()
		move_mod.goto_next_start("@local.scope", "locals")
	end, { desc = "Next scope" })
	map({ "n", "x", "o" }, "]z", function()
		move_mod.goto_next_start("@fold", "folds")
	end, { desc = "Next fold" })
end

return M
