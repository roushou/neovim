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
	if rg then
		vim.health.ok("rg found (primary file enumerator)")
	else
		vim.health.warn("rg not found; falling back to fd/git")
	end
	if fd then
		vim.health.ok("fd found (directory mode and fallback)")
	else
		vim.health.info("fd not found; directory mode derives dirs from files")
	end
	if git then
		vim.health.ok("git found (root detection and status markers)")
	else
		vim.health.warn("git not found; root falls back to cwd and git status is skipped")
	end

	local cfg = config.get()
	local backend = cfg.backend or "ripgrep"
	if backend == "fff" then
		local ok, mod = pcall(require, "fff")
		if ok and type(mod.file_search) == "function" then
			vim.health.ok("backend = fff (fff.file_search available)")
		else
			vim.health.warn("backend = fff but 'fff' is not installed; falling back to ripgrep")
		end
	else
		vim.health.ok("backend = " .. backend)
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
