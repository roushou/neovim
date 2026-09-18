local h = require("tests.harness")
local icons = require("loupe.icons")

h.test("a known filetype gets a glyph and group", function()
	local glyph, hl = icons.get({ rel = "src/main.lua", dir = false })
	h.ok(glyph ~= "")
	h.eq(type(hl), "string")
end)

h.test("unknown files fall back to the generic file glyph", function()
	local glyph = icons.get({ rel = "src/thing.unknownext", dir = false })
	h.eq(glyph, "󰈔")
end)

h.test("directories use the Directory group", function()
	local _, hl = icons.get({ rel = "src", dir = true })
	h.eq(hl, "Directory")
end)
