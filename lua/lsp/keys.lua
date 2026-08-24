--- Buffer-local LSP keymaps, applied on |LspAttach|.

local map = require("util").map

local M = {}

vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(args)
		local client = vim.lsp.get_client_by_id(args.data.client_id)
		client.server_capabilities.semanticTokensProvider = nil

		if client.server_capabilities.hoverProvider then
			map("n", "K", vim.lsp.buf.hover, { buffer = args.buf })
		end

		map("n", "<leader>rn", "<cmd>lua vim.lsp.buf.rename()<cr>", { buffer = args.buf })
		if vim.bo[args.buf].filetype == "rust" then
			map("n", "<leader>ca", function()
				vim.cmd.RustLsp("codeAction")
			end, { buffer = args.buf })
		else
			map("n", "<leader>ca", "<cmd>lua vim.lsp.buf.code_action()<cr>", { buffer = args.buf })
		end
	end,
})

return M
