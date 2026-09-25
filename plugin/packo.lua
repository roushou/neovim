-- Auto-loaded command stub. Kept tiny so `:Packo` exists without requiring the
-- plugin eagerly; the module is loaded on first use.

if vim.g.loaded_packo then
	return
end
vim.g.loaded_packo = true

vim.api.nvim_create_user_command("Packo", function()
	require("packo").open()
end, { desc = "Show the installed plugin dashboard" })
