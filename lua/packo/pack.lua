--- vim.pack data access.
---
--- This is the only module that knows about |vim.pack|; the rest of packo
--- works on the plain row tables returned here. Isolating it keeps the
--- dashboard itself host-agnostic and easy to lift into its own plugin.

local M = {}

--- List every plugin `vim.pack` manages: active in this session and
--- lockfile-only. Git-free and synchronous — tags/branches are fetched on
--- demand by `M.info()`, so listing never spends an event-loop turn.
--- @return table[]
function M.list()
	local rows = {}
	for _, p in ipairs(vim.pack.get(nil, { info = false })) do
		rows[#rows + 1] = {
			name = p.spec.name,
			src = p.spec.src,
			version = p.spec.version,
			path = p.path,
			rev = p.rev,
			active = p.active,
			missing = vim.fn.isdirectory(p.path) ~= 1,
			health = nil, -- nil | "ok" | "drift" | "error"
			health_detail = nil,
		}
	end
	return rows
end

--- Extra git info (tags/branches) for one plugin, or nil. Needs git, so the
--- dashboard calls this only when a detail is actually requested.
--- @return table|nil
function M.info(row)
	if row.missing then
		return nil
	end
	local ok, got = pcall(vim.pack.get, { row.name }, { info = true })
	if ok and got and got[1] then
		return got[1]
	end
	return nil
end

--- Compare the plugin's on-disk HEAD against its lockfile revision, then call
--- `done()`. Runs asynchronously, one shell per plugin, in parallel.
--- @param row table
--- @param done? function
function M.check(row, done)
	done = done or function() end
	if row.missing then
		done()
		return
	end
	vim.system({ "git", "rev-parse", "HEAD" }, { cwd = row.path, text = true }, function(res)
		vim.schedule(function()
			if res.code ~= 0 then
				row.health = "error"
				row.health_detail = "not a git repository"
			else
				local head = vim.trim(res.stdout or "")
				if row.rev and head ~= "" and head ~= row.rev then
					row.health = "drift"
					row.health_detail = ("HEAD %s ≠ lock %s"):format(head:sub(1, 7), row.rev:sub(1, 7))
				else
					row.health = "ok"
				end
			end
			done()
		end)
	end)
end

return M
