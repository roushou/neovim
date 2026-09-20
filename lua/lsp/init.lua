--- LSP entry point: loads the server loader, buffer keymaps and the LSP
--- features (document highlight, :LspInfo, inlay hints).

local M = {}

function M.setup()
	require("lsp.setup")
	require("lsp.keys")
	require("lsp.features.highlight").setup()
	require("lsp.features.info")
	require("lsp.features.endhints")
end

return M
