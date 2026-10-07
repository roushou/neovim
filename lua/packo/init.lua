--- Packo: a dashboard for |vim.pack|.
---
--- Shows every plugin vim.pack manages, its state (active / inactive /
--- missing), and whether its on-disk revision drifted from the lockfile. It
--- changes nothing itself; the `u`/`U` actions hand off to |vim.pack.update()|
--- and `d` to |vim.pack.del()|.
---
--- Public API:
---   require("packo").setup(opts)
---   require("packo").open()
---   require("packo").close()
---   require("packo").toggle()
---   require("packo").is_active()

local M = {}

--- Configure packo. Deep-merged over the defaults (see `packo.config`).
function M.setup(opts)
	require("packo.config").setup(opts)
end

--- Open the dashboard.
function M.open()
	require("packo.dashboard").open()
end

--- Close the dashboard.
function M.close()
	require("packo.dashboard").close()
end

--- Toggle the dashboard.
function M.toggle()
	require("packo.dashboard").toggle()
end

--- Whether the dashboard is open.
function M.is_active()
	return require("packo.dashboard").is_active()
end

return M
