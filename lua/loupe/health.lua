--- :checkhealth loupe
---
--- Reports external dependencies, the configured backend, and the resolved
--- project root. Pure: built-in `vim.health` only.

local config = require("loupe.config")

local M = {}

local function executable(name)
	return vim.fn.executable(name) == 1
end

function M.check()
	vim.health.start("loupe")

	local rg, fd, git = executable("rg"), executable("fd"), executable("git")
	if fd then
		vim.health.ok("fd found (primary file/directory enumerator)")
	else
		vim.health.info("fd not found; files cascade to rg/git and dirs derive from files")
	end
	if rg then
		vim.health.ok("rg found (file fallback)")
	else
		vim.health.info("rg not found; file fallback skips to git")
	end
	if git then
		vim.health.ok("git found (tracked-file fallback, root detection and status markers)")
	else
		vim.health.warn("git not found; root falls back to cwd and git status is skipped")
	end

	local cfg = config.get()
	local engine = cfg.backend or "ripgrep"
	if engine == "fff" then
		local ok, mod = pcall(require, "fff")
		if ok and type(mod.file_search) == "function" then
			vim.health.ok("matcher = fff (fff.file_search available)")
		else
			vim.health.warn("matcher = fff but 'fff' is not installed; falling back to matchfuzzypos")
		end
	else
		vim.health.ok("matcher = " .. engine)
	end

	local backend = require("loupe.backend")
	for _, op in ipairs({ "files", "dirs" }) do
		local id = backend.resolve(op)
		if id then
			vim.health.ok(op .. " backend: " .. id)
		else
			vim.health.warn(op .. " backend: none available")
		end
	end

	local ok, root = pcall(cfg.root)
	if ok and type(root) == "string" and vim.fn.isdirectory(root) == 1 then
		vim.health.ok("project root: " .. root)
	else
		vim.health.warn("project root could not be resolved: " .. tostring(root))
	end

	if not vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = "LoupeMatch" })) then
		vim.health.ok("highlight groups defined")
	else
		vim.health.info("highlight groups not defined yet (open loupe once)")
	end
end

return M
