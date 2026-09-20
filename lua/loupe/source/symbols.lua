--- Workspace symbols source: workspace/symbol across all capable clients.
---
--- Dynamic, like grep: each query change fires a debounced request. Choosing
--- jumps to the symbol (see `loupe.source.jump`).

local jump = require("loupe.source.jump")

return {
	name = "symbols",
	label = "Workspace symbols",
	icon = "",
	backend = { "lsp" },
	search = "symbols",
	choose = jump.choose,
}
