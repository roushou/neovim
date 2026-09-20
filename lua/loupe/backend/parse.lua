--- Output parsing shared by the enumeration backends.
---
--- All backends talk in newline-delimited, root-relative paths, so a single
--- parser covers fd, rg and git. Candidate shape is the one the session,
--- drawer and icons expect: `{ rel, abs, dir }`.

local run = require("loupe.backend.run")

local M = {}

--- Build a candidate from a root-relative path.
function M.candidate(root, rel, dir)
	return { rel = rel, abs = root .. "/" .. rel, dir = dir == true }
end

--- Parse newline-delimited root-relative paths into deduped candidates.
--- Strips a leading `./` and, for directories, the trailing `/` fd emits.
function M.paths(stdout, root, dir)
	local seen, out = {}, {}
	for _, raw in ipairs(run.lines(stdout)) do
		local rel = raw:gsub("^%./", "")
		if dir then
			rel = rel:gsub("/$", "")
		end
		if rel ~= "" and not seen[rel] then
			seen[rel] = true
			out[#out + 1] = M.candidate(root, rel, dir)
		end
	end
	return out
end

--- Derive the set of parent directories from a file list (fd-less fallback).
function M.derive_dirs(files, root)
	local seen, out = {}, {}
	for _, c in ipairs(files) do
		local dir = c.rel:match("^(.*)/[^/]+$")
		if dir and not seen[dir] then
			seen[dir] = true
			out[#out + 1] = M.candidate(root, dir, true)
		end
	end
	return out
end

return M
