--- internal backend: loupe-owned data (the frecency store), no external tool.
---
--- Always available (`exe` is nil).

local frecency = require("loupe.frecency")

local M = {} -- no exe: always available

M.list = {
	recent = function(root, cb)
		cb(frecency.recent(root), true)
	end,
}

return M
