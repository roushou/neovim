--- Headless test runner.
---   nvim --headless -u tests/minimal_init.lua -l tests/run.lua

vim.notify = function() end -- keep test output clean

local harness = require("tests.harness")
for _, spec in ipairs({
	"tests.spec_util_proc",
	"tests.spec_util_textfield",
	"tests.spec_util_debounce",
	"tests.spec_primitives",
	"tests.spec_util_file",
}) do
	require(spec)
end

if not harness.run() then
	vim.cmd("cquit")
end
vim.cmd("qall!")
