--- Backend registry and enumeration facade.
---
--- A backend is a tool adapter exposing `list` operations keyed by capability
--- (`files`, `dirs`, later `changed`, `buffers`, ...). `config.backends` holds
--- per-capability preference lists; the first available backend wins and a
--- failing run cascades to the next. Fuzzy ranking lives in `loupe.matcher`;
--- this module only produces candidates.

local config = require("loupe.config")
local matcher = require("loupe.matcher")
local parse = require("loupe.backend.parse")

local M = { registry = {} }

M.registry.fd = require("loupe.backend.fd")
M.registry.rg = require("loupe.backend.rg")
M.registry.git = require("loupe.backend.git")
M.registry.nvim = require("loupe.backend.nvim")
M.registry.internal = require("loupe.backend.internal")

--- A backend is available when it declares no exe or its exe is on PATH.
local function available(b)
	return b ~= nil and (b.exe == nil or vim.fn.executable(b.exe) == 1)
end

--- First available backend exposing `list[op]`.
--- @return string|nil id, function|nil fn
function M.resolve(op, prefs)
	prefs = prefs or (config.get().backends and config.get().backends[op]) or {}
	for _, id in ipairs(prefs) do
		local b = M.registry[id]
		if available(b) and b.list and b.list[op] then
			return id, b.list[op]
		end
	end
	return nil, nil
end

--- Try each preferred backend in order until one succeeds.
--- `on_done(cands, ok)`; `ok = false` means every backend failed.
function M.resolve_list(op, root, prefs, on_done)
	prefs = prefs or (config.get().backends and config.get().backends[op]) or {}
	local function attempt(i)
		local id = prefs[i]
		if not id then
			on_done({}, false)
			return
		end
		local b = M.registry[id]
		if not (available(b) and b.list and b.list[op]) then
			attempt(i + 1)
			return
		end
		b.list[op](root, function(cands, ok)
			if ok then
				on_done(cands, true)
			else
				attempt(i + 1)
			end
		end)
	end
	attempt(1)
end

--- Enumerate `root` asynchronously; `on_done` receives the candidate list.
--- `mode` is "files" or "dirs"; when no directory enumerator is available (or
--- it finds nothing) directories are derived from the file list.
function M.list(root, mode, on_done)
	if matcher.fff_module() then
		on_done({})
		return
	end
	if mode == "dirs" then
		M.resolve_list("dirs", root, nil, function(cands, ok)
			if ok and #cands > 0 then
				on_done(cands)
			else
				M.resolve_list("files", root, nil, function(files)
					on_done(parse.derive_dirs(files, root))
				end)
			end
		end)
		return
	end
	M.resolve_list("files", root, nil, on_done)
end

--- Rank `cands` against `query` (delegates to `loupe.matcher`).
function M.match(query, cands, max, ctx)
	return matcher.match(query, cands, max, ctx)
end

return M
