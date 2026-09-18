--- File operations on the highlighted entry.
---
--- Every operation is rooted at `ctx.root`; `ctx.item` is the current match's
--- candidate. Functions return the relative path to focus afterwards (or true
--- for a plain mutation), and nil/false when nothing changed.

local M = {}

local function notify(msg, level)
	vim.notify("loupe: " .. msg, level or vim.log.levels.INFO)
end

local function parent(path)
	return vim.fn.fnamemodify(path, ":h")
end

--- Rename/move the current entry to `newrel` (relative to root). This is also
--- the "move" action: the target path may point into another directory.
function M.rename(ctx, newrel)
	local cand = ctx.item.cand
	if newrel == "" or newrel == cand.rel then
		return nil
	end
	local newabs = ctx.root .. "/" .. newrel
	if vim.uv.fs_stat(newabs) then
		notify("already exists: " .. newrel, vim.log.levels.WARN)
		return nil
	end
	vim.fn.mkdir(parent(newabs), "p")
	local ok, err = vim.uv.fs_rename(cand.abs, newabs)
	if not ok then
		notify("rename failed: " .. tostring(err), vim.log.levels.ERROR)
		return nil
	end
	-- Keep an already-open buffer pointed at the new path.
	local buf = vim.fn.bufnr(cand.abs)
	if buf ~= -1 then
		pcall(vim.api.nvim_buf_set_name, buf, newabs)
	end
	cand.rel, cand.abs = newrel, newabs
	notify("renamed to " .. newrel)
	return newrel
end

--- Delete the current entry. Directories are refused (too easy to nuke a tree).
function M.delete(ctx)
	local cand = ctx.item.cand
	if cand.dir then
		notify("refusing to delete a directory", vim.log.levels.WARN)
		return false
	end
	local ok, err = vim.uv.fs_unlink(cand.abs)
	if not ok then
		notify("delete failed: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	local cands = ctx.session.candidates
	for i, c in ipairs(cands) do
		if c == cand then
			table.remove(cands, i)
			break
		end
	end
	notify("deleted " .. cand.rel)
	return true
end

--- Create an empty file at `newrel`, returning it so the caller can focus it.
function M.create(ctx, newrel)
	if newrel == "" then
		return nil
	end
	local newabs = ctx.root .. "/" .. newrel
	if vim.uv.fs_stat(newabs) then
		notify("already exists: " .. newrel, vim.log.levels.WARN)
		return nil
	end
	vim.fn.mkdir(parent(newabs), "p")
	vim.fn.writefile({}, newabs)
	table.insert(ctx.session.candidates, 1, { rel = newrel, abs = newabs, dir = false })
	notify("created " .. newrel)
	return newrel
end

--- Yank the absolute path of the current entry to the unnamed and clipboard regs.
function M.yank(ctx)
	local path = ctx.item.cand.abs
	vim.fn.setreg('"', path)
	vim.fn.setreg("+", path)
	notify("yanked " .. path)
end

return M
