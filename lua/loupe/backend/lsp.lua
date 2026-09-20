--- lsp backend: workspace symbols from attached language servers.
---
--- Availability is dynamic (a client supporting `workspace/symbol` must be
--- attached). Requests go to `ctx.buf`'s clients explicitly because the picker
--- itself runs in a scratch buffer with no LSP attachment. Responses from every
--- client are merged; a 5s safety net delivers whatever arrived if a server
--- never answers.

local parse = require("loupe.backend.parse")

local M = {}

M.available = function()
	return #vim.lsp.get_clients({ method = "workspace/symbol" }) > 0
end

M.search = {
	symbols = function(query, ctx, cb)
		local buf = ctx.buf
		if not (buf and vim.api.nvim_buf_is_valid(buf)) then
			cb({}, true)
			return
		end
		local capable = vim.tbl_filter(function(c)
			return c:supports_method("workspace/symbol", buf)
		end, vim.lsp.get_clients({ bufnr = buf }))
		if #capable == 0 then
			cb({}, true)
			return
		end

		local acc = { n = #capable, done = 0, out = {} }
		local delivered = false
		local timer = vim.uv.new_timer()

		local function deliver()
			if delivered then
				return
			end
			delivered = true
			timer:stop()
			timer:close()
			vim.schedule(function()
				cb(acc.out, true)
			end)
		end

		local function finish()
			acc.done = acc.done + 1
			if acc.done >= acc.n then
				deliver()
			end
		end

		timer:start(5000, 0, vim.schedule_wrap(deliver))

		vim.lsp.buf_request(buf, "workspace/symbol", { query = query }, function(err, result)
			if not err and type(result) == "table" then
				for _, sym in ipairs(result) do
					local loc = sym.location or sym
					if loc and loc.uri and loc.range then
						local path = vim.uri_to_fname(loc.uri)
						local rel = parse.relpath(ctx.root, path)
						local name = sym.name or "?"
						if sym.containerName and sym.containerName ~= "" then
							name = name .. " (" .. sym.containerName .. ")"
						end
						acc.out[#acc.out + 1] = {
							rel = rel,
							abs = path,
							label = name .. "  " .. rel,
							lnum = (loc.range.start and loc.range.start.line + 1) or 1,
							col = 0,
							dir = false,
						}
					end
				end
			end
			finish()
		end)
	end,
}

return M
