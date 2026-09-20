--- rg backend: fallback file enumerator (and the future grep source).
---
--- `rg --files` respects `.gitignore` and skips hidden/binary files just like
--- fd, so it is a safe substitute when fd is unavailable.

local run = require("loupe.backend.run")
local parse = require("loupe.backend.parse")

local M = { exe = "rg" }

M.list = {
	files = function(root, cb)
		run.raw({ "rg", "--files" }, root, function(stdout)
			return parse.paths(stdout, root, false)
		end, cb)
	end,
}

return M
