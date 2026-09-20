--- Files source: every file under the project root.
---
--- Uses the filesystem enumeration facade (`backend.list`), which handles the
--- fd → rg → git preference cascade and directory derivation.

local backend = require("loupe.backend")

return {
	name = "files",
	label = "Files",
	icon = "",
	list = function(root, cb)
		backend.list(root, "files", function(cands)
			cb(cands, true)
		end)
	end,
}
