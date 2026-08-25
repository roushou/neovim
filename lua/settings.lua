vim.g.mapleader = " "

local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.expandtab = true
opt.tabstop = 2
opt.shiftwidth = 2
opt.scrolloff = 8
opt.signcolumn = "yes" -- Always show the sign column
opt.splitright = true
opt.splitbelow = true
-- preview substitutions live
opt.inccommand = "split"
opt.wrap = true
opt.linebreak = true
opt.winborder = "single"
opt.laststatus = 3
-- opt.cmdheight = 0

-- [d / ]d (vim.diagnostic.jump): show a float with the diagnostic text.
-- jump defaults to NO float at all, so enable it. The float stays open
-- until the cursor actually moves (nvim's default close_events would close
-- it instantly because a spurious same-position CursorMoved fires when the
-- float opens in this config — see the CursorMoved handler below).
vim.diagnostic.config({
	float = { close_events = {} },
	jump = { float = true },
})

-- Close diagnostic floats on real cursor movement, ignoring the spurious
-- same-position CursorMoved emitted on the float's opening redraw.
local diag_float_group = vim.api.nvim_create_augroup("diag_float_close", { clear = true })

local open_float = vim.diagnostic.open_float
---@diagnostic disable-next-line: duplicate-set-field
vim.diagnostic.open_float = function(opts, ...)
	local float_bufnr, winnr = open_float(opts, ...)
	if winnr then
		vim.b[vim.api.nvim_get_current_buf()].diag_float = {
			win = winnr,
			pos = vim.api.nvim_win_get_cursor(0),
		}
	end
	return float_bufnr, winnr
end

vim.api.nvim_create_autocmd("CursorMoved", {
	group = diag_float_group,
	callback = function()
		local buf = vim.api.nvim_get_current_buf()
		local f = vim.b[buf].diag_float
		if f and vim.api.nvim_win_is_valid(f.win) then
			local pos = vim.api.nvim_win_get_cursor(0)
			if pos[1] ~= f.pos[1] or pos[2] ~= f.pos[2] then
				vim.api.nvim_win_close(f.win, true)
				vim.b[buf].diag_float = nil
			end
		end
	end,
})

vim.api.nvim_create_autocmd("FileType", {
	pattern = { "cpp", "wgsl", "go", "swift", "solidity", "odin" },
	callback = function()
		vim.opt_local.shiftwidth = 4
		vim.opt_local.tabstop = 4
		if vim.bo.filetype == "odin" then
			vim.opt_local.expandtab = false
		end
	end,
})

vim.api.nvim_create_autocmd("FileType", {
	pattern = "rust",
	callback = function()
		vim.lsp.inlay_hint.enable(false)
	end,
})

vim.api.nvim_create_autocmd("FileType", {
	pattern = "cpp",
	callback = function()
		vim.lsp.inlay_hint.enable(true)
	end,
})

vim.filetype.add({ extension = { mdx = "mdx", odin = "odin" } })
