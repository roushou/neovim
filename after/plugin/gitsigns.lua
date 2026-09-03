local map = require("util").map

require("gitsigns").setup({})

map("n", "g[", require("gitsigns").prev_hunk, { desc = "Gitsigns: prev hunk" })
map("n", "g]", require("gitsigns").next_hunk, { desc = "Gitsigns: next hunk" })
map("n", "<leader>gp", require("gitsigns").preview_hunk_inline, { desc = "Gitsigns: preview hunk inline" })
map("n", "<leader>gd", require("gitsigns").diffthis, { desc = "Gitsigns: diff this" })
