--- Global LSP handler overrides (set once, not per-attach).
--- Pure logic: no autocmds, keymaps or UI. Loaded by lsp/init.lua.

local M = {}

vim.lsp.handlers["textDocument/hover"] = function(_, result, ctx, config)
	config = vim.tbl_deep_extend("force", config or {}, { border = "single", title = "hover" })
	vim.lsp.handlers.hover(_, result, ctx, config)
end
vim.lsp.handlers["textDocument/signatureHelp"] = function(_, result, ctx, config)
	config = vim.tbl_deep_extend("force", config or {}, { border = "single" })
	vim.lsp.handlers.signature_help(_, result, ctx, config)
end

return M
