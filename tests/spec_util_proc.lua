local h = require("tests.harness")
local proc = require("util.proc")

h.test("proc.sync captures stdout", function()
	local out, err = proc.sync({ "sh", "-c", "printf hi" })
	h.eq(err, nil)
	h.eq(out, "hi")
end)

h.test("proc.sync reports failure via stderr", function()
	local out, err = proc.sync({ "sh", "-c", "echo boom >&2; exit 3" })
	h.eq(out, nil)
	h.eq(err, "boom")
end)

h.test("proc.lines drops empty lines", function()
	local lines, err = proc.lines({ "sh", "-c", "printf 'a\\n\\nb\\n'" })
	h.eq(err, nil)
	h.eq(lines, { "a", "b" })
end)

h.test("proc.async invokes the callback", function()
	local done, got = false, nil
	local spawned = proc.async({ "sh", "-c", "printf ok" }, {}, function(res)
		got = res.stdout
		done = true
	end)
	h.ok(spawned)
	vim.wait(5000, function()
		return done
	end, 20)
	h.eq(got, "ok")
end)
