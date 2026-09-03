--- Per-filetype editor defaults and filetype detection.

-- 4-space indentation (the default is 2); odin also uses hard tabs.
local INDENT_4 = { "cpp", "wgsl", "go", "swift", "solidity", "odin" }

vim.api.nvim_create_autocmd("FileType", {
	pattern = INDENT_4,
	callback = function(ev)
		vim.opt_local.shiftwidth = 4
		vim.opt_local.tabstop = 4
		if ev.match == "odin" then
			vim.opt_local.expandtab = false
		end
	end,
})

vim.filetype.add({ extension = { mdx = "mdx", odin = "odin" } })
