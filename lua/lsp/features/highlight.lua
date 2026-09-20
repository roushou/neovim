--- Highlight all occurrences of the symbol under the cursor via
--- textDocument/documentHighlight (references in write access get
--- LspReferenceWrite). Gated on the server's documentHighlightProvider.

local theme = require("ui.theme")
local util = require("util")

local M = {}

local AUGROUP = util.augroup("lsp_document_highlight")

-- kanagawa leaves LspReferenceRead undefined; fall back to LspReferenceText
-- so read references are visible (default keeps a colorscheme's own value).
theme.hl("LspReferenceRead", { link = "LspReferenceText", default = true })

--- Only run when a capable client is attached to this buffer.
local function capable(bufnr)
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
		if client:supports_method("textDocument/documentHighlight") then
			return true
		end
	end
	return false
end

function M.setup()
	vim.api.nvim_create_autocmd("LspAttach", {
		group = AUGROUP,
		callback = function(args)
			if not capable(args.buf) then
				return
			end
			local group = util.augroup("lsp_document_highlight_" .. args.buf)
			vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
				group = group,
				buf = args.buf,
				callback = function()
					vim.lsp.buf.document_highlight()
				end,
			})
			vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
				group = group,
				buf = args.buf,
				callback = function()
					vim.lsp.buf.clear_references()
				end,
			})
		end,
	})

	vim.api.nvim_create_autocmd("LspDetach", {
		group = AUGROUP,
		callback = function(args)
			pcall(vim.lsp.buf.clear_references)
		end,
	})
end

return M
