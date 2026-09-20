local h = require("tests.harness")
local parse = require("loupe.backend.parse")

h.test("paths parses, strips ./ and builds abs", function()
	local out = parse.paths("./a.lua\nsrc/b.lua\n", "/root", false)
	h.eq(#out, 2)
	h.eq(out[1], { rel = "a.lua", abs = "/root/a.lua", dir = false })
	h.eq(out[2], { rel = "src/b.lua", abs = "/root/src/b.lua", dir = false })
end)

h.test("paths marks directories and strips the trailing slash", function()
	local out = parse.paths("src/\nlib/\n", "/root", true)
	h.eq(out[1], { rel = "src", abs = "/root/src", dir = true })
	h.eq(out[2], { rel = "lib", abs = "/root/lib", dir = true })
end)

h.test("paths dedupes and drops blank lines", function()
	local out = parse.paths("a\n\na\nb\n", "/r", false)
	h.eq(#out, 2)
	h.eq(out[1].rel, "a")
	h.eq(out[2].rel, "b")
end)

h.test("paths tolerates empty output", function()
	h.eq(parse.paths("", "/r", false), {})
	h.eq(parse.paths(nil, "/r", true), {})
end)

h.test("derive_dirs extracts parents, ignoring root files", function()
	local files = {
		{ rel = "a.lua", abs = "/r/a.lua" },
		{ rel = "src/b.lua", abs = "/r/src/b.lua" },
		{ rel = "src/deep/c.lua", abs = "/r/src/deep/c.lua" },
	}
	local out = parse.derive_dirs(files, "/r")
	h.eq(#out, 2)
	h.eq(out[1], { rel = "src", abs = "/r/src", dir = true })
	h.eq(out[2], { rel = "src/deep", abs = "/r/src/deep", dir = true })
end)
