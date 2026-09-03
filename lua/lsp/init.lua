--- LSP entry point: loads the server loader, buffer keymaps and the LSP
--- features (document highlight, :LspInfo, symbol pickers, inlay hints).

local M = {}

require("lsp.setup")
require("lsp.keys")
require("lsp.features.highlight").setup()
require("lsp.features.info")
require("lsp.features.pick")
require("lsp.features.endhints")

return M
