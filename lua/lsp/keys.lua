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
	end,
})

return M
