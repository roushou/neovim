--- Symbols source: workspace symbols (LSP `workspace/symbol`).
---
--- Dynamic, like grep: each query change fires a debounced request at every
--- capable client attached to the buffer the picker was opened from.

return {
	name = "symbols",
	label = "Symbols",
	icon = "",
	backend = { "lsp" },
	search = "symbols",
}
