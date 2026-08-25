--- Buffer-local LSP keymaps, applied on |LspAttach|.

local map = require("util").map

local M = {}

vim.api.nvim_create_autocmd("LspAttach", {
	callback = function(args)
		local client = vim.lsp.get_client_by_id(args.data.client_id)
		if not client then
			return -- client stopped between LspAttach and this callback
		end
		client.server_capabilities.semanticTokensProvider = nil

		if client:supports_method("textDocument/hover", args.buf) then
			map("n", "K", function()
				vim.lsp.buf.hover({ border = "single", title = "hover" })
			end, { buf = args.buf, desc = "Hover" })
		end

		if client:supports_method("textDocument/rename", args.buf) then
			map("n", "<leader>rn", "<cmd>lua vim.lsp.buf.rename()<cr>", { buf = args.buf, desc = "Rename symbol" })
		end
		if client:supports_method("textDocument/codeAction", args.buf) then
			if vim.bo[args.buf].filetype == "rust" then
				map("n", "<leader>ca", function()
					vim.cmd.RustLsp("codeAction")
				end, { buf = args.buf, desc = "Code action (rust)" })
			else
				map(
					"n",
					"<leader>ca",
					"<cmd>lua vim.lsp.buf.code_action()<cr>",
					{ buf = args.buf, desc = "Code action" }
				)
			end
		end
	end,
})

return M
