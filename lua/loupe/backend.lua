--- File enumeration + fuzzy ranking.
---
--- Backend contract (so alternate engines can drop in):
---   list(root, mode, on_done)     -> on_done({ { rel, abs, dir }, ... })
---   match(query, cands, max, ctx) -> { { cand, positions }, ... }
---
--- Two engines implement it, selected by `config.backend`:
---   "ripgrep" (default): shell out once to enumerate, rank with
---                        `vim.fn.matchfuzzypos` (C-implemented).
---   "fff":               `require("fff").file_search` (Rust engine); enumerates
---                        internally, so `list` is a no-op.
--- The fff path falls back to ripgrep when fff is not installed.

local config = require("loupe.config")
local proc = require("util.proc")

local M = {}

local FILE_CMDS = {
	{ "rg", "--files" },
	{ "fd", "--type", "f" },
	{ "git", "ls-files" },
}

local DIR_CMDS = {
	{ "fd", "--type", "d" },
}

-- ripgrep engine -------------------------------------------------------------

local function parse(stdout, root, dir)
	local seen, cands = {}, {}
	for _, raw in ipairs(vim.split(stdout or "", "\n", { plain = true })) do
		local rel = raw:gsub("^%./", "")
		if rel ~= "" and not seen[rel] then
			seen[rel] = true
			cands[#cands + 1] = { rel = rel, abs = root .. "/" .. rel, dir = dir and true or false }
		end
	end
	return cands
end

--- Derive the set of parent directories from a file list (fd fallback).
local function derive_dirs(files)
	local seen, out = {}, {}
	for _, c in ipairs(files) do
		local dir = c.rel:match("^(.*)/[^/]+$")
		if dir and not seen[dir] then
			seen[dir] = true
			out[#out + 1] = { rel = dir, abs = c.abs:sub(1, #c.abs - #c.rel + #dir), dir = true }
		end
	end
	return out
end

local function run_async(root, cmds, i, dir, on_done)
	if i > #cmds then
		on_done({})
		return
	end
	local ok = proc.async(cmds[i], { cwd = root }, function(res)
		if res.code ~= 0 then
			run_async(root, cmds, i + 1, dir, on_done)
			return
		end
		vim.schedule(function()
			on_done(parse(res.stdout, root, dir))
		end)
	end)
	if not ok then
		on_done({})
	end
end

local function rg_list(root, mode, on_done)
	if mode ~= "dirs" then
		run_async(root, FILE_CMDS, 1, false, on_done)
		return
	end
	run_async(root, DIR_CMDS, 1, true, function(cands)
		if #cands > 0 then
			on_done(cands)
		else
			-- no fd: derive directories from the file list
			run_async(root, FILE_CMDS, 1, false, function(files)
				on_done(derive_dirs(files))
			end)
		end
	end)
end

local function rg_match(query, cands, max)
	local out = {}
	if query == "" then
		for i = 1, math.min(max, #cands) do
			out[i] = { cand = cands[i], positions = {} }
		end
		return out
	end

	local by_rel, paths = {}, {}
	for _, c in ipairs(cands) do
		by_rel[c.rel] = c
		paths[#paths + 1] = c.rel
	end

	-- matchfuzzypos returns a single 3-element list: { matches, positions, scores }.
	local res = vim.fn.matchfuzzypos(paths, query)
	local matches, positions = res[1], res[2]
	for i = 1, math.min(max, #matches) do
		local cand = by_rel[matches[i]]
		if cand then
			out[#out + 1] = { cand = cand, positions = positions[i] or {} }
		end
	end
	return out
end

-- fff engine (optional) ------------------------------------------------------

local function fff_module()
	if config.get().backend ~= "fff" then
		return nil
	end
	local ok, mod = pcall(require, "fff")
	if ok and type(mod.file_search) == "function" then
		return mod
	end
	return nil
end

local function fff_match(mod, query, max, ctx)
	local mode = ctx and ctx.mode == "dirs" and "directories" or "files"
	local ok, res = pcall(mod.file_search, query, {
		cwd = ctx and ctx.root or nil,
		mode = mode,
		max_results = max,
	})
	if not ok or type(res) ~= "table" then
		return nil
	end
	local out = {}
	for _, item in ipairs(res.items or {}) do
		local rel = item.relative_path
		if rel then
			-- fff already ranks; no per-character positions are mapped here.
			out[#out + 1] = {
				cand = {
					rel = rel,
					abs = ctx and ctx.root and (ctx.root .. "/" .. rel) or rel,
					dir = item.type == "directory",
				},
				positions = {},
			}
		end
	end
	return out
end

-- public --------------------------------------------------------------------

--- Enumerate `root` asynchronously; `on_done` receives the candidate list.
function M.list(root, mode, on_done)
	if fff_module() then
		on_done({})
		return
	end
	rg_list(root, mode, on_done)
end

--- Rank `cands` against `query`, returning at most `max` results.
--- `ctx` is { root, mode }.
function M.match(query, cands, max, ctx)
	local mod = fff_module()
	if mod then
		local res = fff_match(mod, query, max, ctx)
		if res then
			return res
		end
	end
	return rg_match(query, cands, max)
end

return M
