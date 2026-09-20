--- git backend: tracked-file enumerator (last-resort file fallback).
---
--- `git ls-files` only lists tracked files, so it misses untracked-but-not-
--- ignored ones; it exists purely to keep the picker usable with neither fd
--- nor rg installed.

local run = require("loupe.backend.run")
local parse = require("loupe.backend.parse")

local M = { exe = "git" }

M.list = {
	files = function(root, cb)
		run.raw({ "git", "ls-files" }, root, function(stdout)
			return parse.paths(stdout, root, false)
		end, cb)
	end,
}

return M
