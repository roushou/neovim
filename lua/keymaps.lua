local map = require("util").map

-- Insert
map("i", "jj", "<esc>", { desc = "Escape" })
map("i", "jk", "<esc>", { desc = "Escape" })

-- Normal
map("n", "j", "gj", { desc = "Soft down" })
map("n", "k", "gk", { desc = "Soft up" })
map("n", "<leader>w", ":w<cr>", { desc = "Save buffer" })
map("n", "<leader>q", ":q<cr>", { desc = "Quit" })
map("n", "<C-h>", "<C-w>h", { desc = "Window left" })
map("n", "<C-j>", "<C-w>j", { desc = "Window down" })
map("n", "<C-k>", "<C-w>k", { desc = "Window up" })
map("n", "<C-l>", "<C-w>l", { desc = "Window right" })
map("n", "<C-n>", "<cmd>Neotree toggle<cr>", { desc = "Toggle file explorer" })
map("n", "<C-p>", "<cmd>Pick files<cr>", { desc = "Pick file" })
map("n", "<leader>fw", "<cmd>Pick grep_live<cr>", { desc = "Live grep" })
map("n", "H", function()
	require("tabline").cycle(-1)
end, { desc = "Previous buffer" })
map("n", "L", function()
	require("tabline").cycle(1)
end, { desc = "Next buffer" })
map("n", "<leader>x", "<cmd>lua MiniBufremove.delete()<cr>", { desc = "Close buffer" })

-- Visual
map("v", "<", "<gv", { desc = "Indent out" })
map("v", ">", ">gv", { desc = "Indent in" })
map("v", "<leader>y", '"+y', { desc = "Yank to clipboard" })
map("v", "<leader>p", '"+p', { desc = "Paste from clipboard" })
