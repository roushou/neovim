--- Diagnostics source: every diagnostic across open documents.
---
--- Static; candidates carry `lnum`/`col`, so choosing jumps to the diagnostic.

local jump = require("loupe.source.jump")

return {
	name = "diagnostics",
	label = "Diagnostics",
	icon = "",
	backend = { "nvim" },
	choose = jump.choose,
}
