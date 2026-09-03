--- LSP entry point: loads config, handlers, keys and the :LspInfo UI.

local map = require("util").map

local M = {}

require("lsp.setup")
require("lsp.keys")
require("lsp.highlight").setup()
require("lsp.info")
require("lsp.pick")
require("lsp.endhints")

-- LSP status overview (:LspInfo) — custom, no plugin
map("n", "<leader>li", "<cmd>LspInfo<cr>", { desc = "LSP info" })

return M
