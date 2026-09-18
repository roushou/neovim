local h = require("tests.harness")
local debounce = require("util.debounce")

h.test("debounce coalesces rapid calls into the last one", function()
	local calls, last = 0, nil
	local d = debounce.new(20, function(v)
		calls = calls + 1
		last = v
	end)
	d:call(1)
	d:call(2)
	d:call(3)
	vim.wait(1000, function()
		return calls > 0
	end, 5)
	h.eq(calls, 1)
	h.eq(last, 3)
end)

h.test("debounce cancel prevents the call", function()
	local fired = false
	local d = debounce.new(20, function()
		fired = true
	end)
	d:call()
	d:cancel()
	vim.wait(200, function()
		return false
	end, 20)
	h.eq(fired, false)
end)
