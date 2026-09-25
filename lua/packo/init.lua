--- Packo: a read-only dashboard for |vim.pack|.
---
--- Shows every plugin vim.pack manages, its state (active / inactive /
--- missing), and whether its on-disk revision drifted from the lockfile. It
--- never updates or deletes anything; the `u`/`U` actions hand off to
--- |vim.pack.update()|.
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
