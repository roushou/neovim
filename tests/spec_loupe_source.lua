local h = require("tests.harness")
local source = require("loupe.source")

h.test("built-in sources are registered", function()
	for _, name in ipairs({ "files", "dirs", "buffers", "recent", "changed" }) do
		local s = source.get(name)
		h.ok(s, name .. " missing")
		h.eq(s.name, name)
	end
end)

h.test("load dispatches a function source", function()
	local fake = {
		name = "fake_fn",
		list = function(_, cb)
			cb({ { rel = "x" } }, true)
		end,
	}
	local got
	source.load(fake, "/r", function(cands, ok)
		got = { cands, ok }
	end)
	h.eq(got[1][1].rel, "x")
	h.eq(got[2], true)
end)

h.test("load resolves a backend op source", function()
	local backend = require("loupe.backend")
	backend.registry.srcfake = { list = {
		srcop = function(_, cb)
			cb({ { rel = "op" } }, true)
		end,
	} }
	local got
	source.load({ name = "srcop", list = "srcop", backend = { "srcfake" } }, "/r", function(cands, ok)
		got = { cands, ok }
	end)
	h.eq(got[1][1].rel, "op")
	h.eq(got[2], true)
	backend.registry.srcfake = nil
end)

h.test("load reports failure when no backend is available", function()
	local got
	source.load({ name = "nope", list = "nope", backend = { "ghost" } }, "/r", function(cands, ok)
		got = { cands, ok }
	end)
	h.eq(got, { {}, false })
end)
