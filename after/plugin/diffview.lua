local map = require("util").map
local actions = require("diffview.actions")

require("diffview").setup({
	keymaps = {
		view = {
			{ "n", "q", actions.close, { desc = "Close menu" } },
		},
		file_panel = {
			{ "n", "q", actions.close, { desc = "Close menu" } },
		},
		file_history_panel = {
			{ "n", "q", actions.close, { desc = "Close menu" } },
		},
	},
})

map("n", "<leader>gv", function()
	if next(require("diffview.lib").views) == nil then
		vim.cmd("DiffviewOpen")
	else
		vim.cmd("DiffviewClose")
	end
end, { desc = "Toggle diffview" })
