--- `:checkhealth packo`.

local M = {}

function M.check()
	local health = vim.health
	health.start("packo")

	if vim.fn.executable("git") == 1 then
		health.ok("git: " .. vim.fn.exepath("git"))
	else
		health.error("`git` not found (required by vim.pack)")
	end

	local ok, rows = pcall(require("packo.pack").list)
	if not ok then
		health.error("vim.pack unavailable: " .. tostring(rows))
		return
	end

	local active, inactive, missing = 0, 0, 0
	for _, row in ipairs(rows) do
		if row.missing then
			missing = missing + 1
		elseif row.active then
			active = active + 1
		else
			inactive = inactive + 1
		end
	end
	health.info(("%d plugins: %d active, %d inactive, %d missing"):format(#rows, active, inactive, missing))
end

return M
