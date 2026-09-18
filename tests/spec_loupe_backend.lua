local h = require("tests.harness")
local backend = require("loupe.backend")

local CANDS = {
	{ rel = "src/main.lua", abs = "/x/src/main.lua" },
	{ rel = "README.md", abs = "/x/README.md" },
	{ rel = "src/util.lua", abs = "/x/src/util.lua" },
}

h.test("match ranks candidates and returns positions", function()
	local out = backend.match("main", CANDS, 10)
	h.eq(#out, 1)
	h.eq(out[1].cand.rel, "src/main.lua")
	h.ok(#out[1].positions > 0)
end)

h.test("empty query returns candidates in order, capped", function()
	local cands = {}
	for i = 1, 10 do
		cands[i] = { rel = "f" .. i, abs = "/x/f" .. i }
	end
	local out = backend.match("", cands, 3)
	h.eq(#out, 3)
	h.eq(out[1].cand.rel, "f1")
end)

h.test("match returns nothing for no hits", function()
	h.eq(backend.match("zzzzz", CANDS, 10), {})
end)
