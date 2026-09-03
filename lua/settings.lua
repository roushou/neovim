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
