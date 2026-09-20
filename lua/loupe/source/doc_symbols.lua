--- Document symbols source: symbols in the buffer the picker was opened from.
---
--- Static: the LSP returns the whole symbol tree at once and the session
--- fuzzy-filters it client-side. Choosing jumps within the buffer (see
--- `loupe.source.jump`).

local jump = require("loupe.source.jump")

return {
	name = "doc_symbols",
	label = "Document symbols",
	icon = "",
	backend = { "lsp" },
	choose = jump.choose,
}
