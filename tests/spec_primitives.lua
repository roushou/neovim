local h = require("tests.harness")
local util = require("util")
local hl = require("ui.hl")
local theme = require("ui.theme")

h.test("attach_once runs the callback once per buffer", function()
	local buf = vim.api.nvim_create_buf(false, true)
	local n = 0
	h.eq(
		util.attach_once(buf, "prims_attach", function()
			n = n + 1
		end),
		true
	)
	h.eq(
		util.attach_once(buf, "prims_attach", function()
			n = n + 1
		end),
		false
	)
	h.eq(n, 1)
end)

h.test("attach_once keys are independent per buffer", function()
	local a = vim.api.nvim_create_buf(false, true)
	local b = vim.api.nvim_create_buf(false, true)
	local n = 0
	util.attach_once(a, "prims_attach2", function()
		n = n + 1
	end)
	util.attach_once(b, "prims_attach2", function()
		n = n + 1
	end)
	h.eq(n, 2)
end)

h.test("augroup clears an existing group of the same name", function()
	local id1 = util.augroup("prims_group")
	vim.api.nvim_create_autocmd("User", { group = id1, pattern = "X", callback = function() end })
	local id2 = util.augroup("prims_group")
	h.eq(id1, id2)
	h.eq(#vim.api.nvim_get_autocmds({ group = id2 }), 0)
end)

h.test("hl.line marks the whole line", function()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello" })
	local ns = vim.api.nvim_create_namespace("prims_hl_line")
	hl.line(buf, ns, 0, "Error")
	local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
	h.eq(#marks, 1)
	h.eq(marks[1][4].line_hl_group, "Error")
end)

h.test("hl.sign sets a sign extmark", function()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello" })
	local ns = vim.api.nvim_create_namespace("prims_hl_sign")
	hl.sign(buf, ns, 0, "E", "Error")
	local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
	h.eq(marks[1][4].sign_text:sub(1, 1), "E")
	h.eq(marks[1][4].sign_hl_group, "Error")
end)

h.test("theme.hl defines a group and re-applies it on ColorScheme", function()
	theme.hl("PrimsTestHl", function()
		return { fg = 0x123456 }
	end)
	h.eq(vim.api.nvim_get_hl(0, { name = "PrimsTestHl" }).fg, 0x123456)
	vim.api.nvim_exec_autocmds("ColorScheme", {})
	h.eq(vim.api.nvim_get_hl(0, { name = "PrimsTestHl" }).fg, 0x123456)
end)
