--- Highlight all occurrences of the symbol under the cursor via
--- textDocument/documentHighlight (references in write access get
--- LspReferenceWrite). Gated on the server's documentHighlightProvider.

local M = {}

local AUGROUP = vim.api.nvim_create_augroup("lsp_document_highlight", { clear = true })

-- kanagawa leaves LspReferenceRead undefined; fall back to LspReferenceText
-- so read references are visible, re-applied on colorscheme changes
local function ensure_highlights()
	if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "LspReferenceRead" })) then
		vim.api.nvim_set_hl(0, "LspReferenceRead", { link = "LspReferenceText" })
	end
end

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
	ensure_highlights()
	vim.api.nvim_create_autocmd("ColorScheme", { group = AUGROUP, callback = ensure_highlights })
	vim.api.nvim_create_autocmd("LspAttach", {
		group = AUGROUP,
		callback = function(args)
			if not capable(args.buf) then
				return
			end
			local group = vim.api.nvim_create_augroup("lsp_document_highlight_" .. args.buf, { clear = true })
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
