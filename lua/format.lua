--- Format buffers through external binaries.
---
--- - M.format(bufnr)   run configured formatters (LSP fallback if missing)
--- - M.formatexpr()    'formatexpr' impl — makes gq/gw use the formatters
--- - M.attach()        wire up format-on-save (configured filetypes only)

local M = {}

local FORMATTERS = {
	lua = { { cmd = { "stylua", "-" } } },
	rust = { { cmd = { "rustfmt", "--emit", "stdout" } } },
	odin = { { cmd = { "odinfmt", "-stdin" } } },
}

--- Pipe `lines` through one formatter process; return new lines.
local function pipe(lines, fmt)
	local output = vim.system(fmt.cmd, {
		stdin = table.concat(lines, "\n"),
		text = true,
	}):wait()
	if output.code ~= 0 then
		error(("%s failed (%d): %s"):format(fmt.cmd[1], output.code, vim.trim(output.stderr or "")))
	end
	return vim.split(vim.trim(output.stdout or ""), "\n", { trimempty = true })
end

--- Replace `lines` into `bufnr` between `row1`/`row2` (0-indexed, inclusive),
--- joining with the preceding undo step and keeping the cursor/view put.
local function apply(bufnr, row1, row2, lines)
	local win = vim.fn.bufwinid(bufnr)
	local view = win ~= -1 and vim.fn.winsaveview() or nil
	pcall(vim.cmd, "undojoin")
	vim.api.nvim_buf_set_lines(bufnr, row1, row2 + 1, false, lines)
	if view then
		vim.fn.winrestview(view)
	end
end

--- Run configured external formatters over `lines`; nil on any failure
--- (nothing configured / empty input / formatter error, which is notified).
function M.run(lines, filetype)
	local fmts = FORMATTERS[filetype]
	if not fmts or #lines == 0 or vim.trim(table.concat(lines)) == "" then
		return
	end
	local ok, result = pcall(function()
		for _, f in ipairs(fmts) do
			lines = pipe(lines, f)
		end
		return lines
	end)
	if not ok then
		vim.notify(result, vim.log.levels.WARN, { title = "format" })
		return
	end
	return result
end

--- Format a buffer: configured formatters first, LSP server as fallback.
function M.format(bufnr)
	bufnr = bufnr or 0
	if not FORMATTERS[vim.bo[bufnr].filetype] then
		vim.lsp.buf.format({ bufnr = bufnr })
		return
	end
	local row1, row2 = 0, vim.api.nvim_buf_line_count(bufnr) - 1
	local lines = M.run(vim.api.nvim_buf_get_lines(bufnr, row1, -1, false), vim.bo[bufnr].filetype)
	if lines then
		apply(bufnr, row1, row2, lines)
	end
end

--- 'formatexpr' implementation so gq/gw route through the formatters.
--- Formats exactly the requested line range; falls back to the internal
--- (LSP-then-builtin) formatexpr for unconfigured filetypes.
function M.formatexpr()
	local bufnr = vim.api.nvim_get_current_buf()
	local lnum1, count = vim.v.lnum, vim.v.count
	if not FORMATTERS[vim.bo[bufnr].filetype] then
		return vim.lsp.formatexpr({ lnum = lnum1, count = count })
	end
	local row1, row2 = lnum1 - 1, lnum1 + count - 2
	local lines = M.run(vim.api.nvim_buf_get_lines(bufnr, row1, row2, false), vim.bo[bufnr].filetype)
	if lines then
		apply(bufnr, row1, row2, lines)
	end
	return 0
end

--- Format-on-save for filetypes with configured formatters.
function M.attach()
	-- route gq/gw through the formatters too
	vim.o.formatexpr = "v:lua.require'format'.formatexpr()"
	vim.api.nvim_create_autocmd("BufWritePre", {
		group = vim.api.nvim_create_augroup("format_on_save", { clear = true }),
		callback = function(args)
			if FORMATTERS[vim.bo[args.buf].filetype] then
				M.format(args.buf)
			end
		end,
	})
end

return M
