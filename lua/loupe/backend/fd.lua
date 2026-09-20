--- fd backend: the primary file and directory enumerator.
---
--- `fd` is purpose-built for path finding, respects `.gitignore` and skips
--- hidden entries by default, and is fast on large trees. With no search
--- pattern it lists everything under the cwd, relative and unprefixed.

local run = require("loupe.backend.run")
local parse = require("loupe.backend.parse")

local M = { exe = "fd" }

M.list = {
	files = function(root, cb)
		run.raw({ "fd", "--type", "f" }, root, function(stdout)
			return parse.paths(stdout, root, false)
		end, cb)
	end,
	dirs = function(root, cb)
		run.raw({ "fd", "--type", "d" }, root, function(stdout)
			return parse.paths(stdout, root, true)
		end, cb)
	end,
}

return M
