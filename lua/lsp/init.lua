--- LSP entry point: loads config, handlers, keys and the :LspInfo UI.
--- Required by init.lua (`require("lsp")` resolves here).

local map = require("util").map

local M = {}

require("lsp.config")
require("lsp.handlers")
require("lsp.keys")
require("lsp.info")
require("lsp.pick")

-- LSP status overview (:LspInfo) — custom, no plugin
map("n", "<leader>li", "<cmd>LspInfo<cr>", { desc = "LSP info" })

return M
