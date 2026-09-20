local h = require("tests.harness")
local file = require("util.file")
local buflib = require("ui.buf")

local function tmpfile(lines, mode)
	local path = vim.fn.tempname()
	if mode == "b" then
		local f = assert(io.open(path, "wb"))
		f:write(lines)
		f:close()
	else
		vim.fn.writefile(lines, path)
	end
	return path
end

h.test("is_text distinguishes text, binary and missing", function()
	h.eq(file.is_text(tmpfile({ "hello" })), true)
	h.eq(file.is_text(tmpfile("a\0b", "b")), false)
	h.eq(file.is_text(vim.fn.tempname() .. "/nope"), nil)
end)

h.test("read bounds lines and reports truncation", function()
	local path = tmpfile({ "1", "2", "3", "4" })
	local lines, err, truncated = file.read(path, 2)
	h.eq(err, nil)
	h.eq(lines, { "1", "2" })
	h.eq(truncated, true)

	local all, aerr, atrunc = file.read(path)
	h.eq(aerr, nil)
	h.eq(#all, 4)
	h.eq(atrunc, false)
end)

h.test("read reports unreadable files", function()
	local lines, err = file.read(vim.fn.tempname() .. "/nope", 10)
	h.eq(lines, nil)
	h.ok(err ~= nil)
end)

h.test("should_highlight is true for a small buffer", function()
	local b = buflib.scratch({})
	vim.api.nvim_buf_set_lines(b, 0, -1, false, { "local x = 1" })
	h.eq(file.should_highlight(b), true)
end)

h.test("highlight with an empty filetype stays valid", function()
	local b = buflib.scratch({})
	vim.api.nvim_buf_set_lines(b, 0, -1, false, { "local x = 1" })
	file.highlight(b, "")
	file.highlight(b, "lua")
	h.ok(vim.api.nvim_buf_is_valid(b))
end)
