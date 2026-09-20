--- rg backend: fallback file enumerator (and the future grep source).
---
--- `rg --files` respects `.gitignore` and skips hidden/binary files just like
--- fd, so it is a safe substitute when fd is unavailable.

local run = require("loupe.backend.run")
local parse = require("loupe.backend.parse")

local M = { exe = "rg" }

M.list = {
	files = function(ctx, cb)
		run.raw({ "rg", "--files" }, ctx.root, function(stdout)
			return parse.paths(stdout, ctx.root, false)
		end, cb)
	end,
}

M.search = {
	--- Live content search. `--vimgrep` gives path:line:col:text; smart-case
	--- keeps lowercase queries case-insensitive without extra config.
	grep = function(query, ctx, cb)
		if query == "" then
			cb({}, true)
			return
		end
		run.raw(
			{
				"rg",
				"--vimgrep",
				"--no-heading",
				"--color",
				"never",
				"--smart-case",
				"--max-count",
				"30",
				"--",
				query,
			},
			ctx.root,
			function(stdout)
				return parse.vimgrep(stdout, ctx.root)
			end,
			cb
		)
	end,
}

return M
