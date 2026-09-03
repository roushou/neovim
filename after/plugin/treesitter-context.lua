local map = require("util").map

require("treesitter-context").setup({})

map("n", "[c", function()
	require("treesitter-context").go_to_context(vim.v.count1)
end, { desc = "Go to context" })
