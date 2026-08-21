-- 0.12 built-in undo tree.
vim.cmd("packadd nvim.undotree")

-- Diff windows: label them in the winbar and show the fold column.
vim.opt.diffopt:append("foldcolumn:2")

-- Winbar for diff windows (side + filename + hints); cleared on diffoff.
local function setup_diff_winbar(winid)
	winid = winid or vim.api.nvim_get_current_win()
	vim.api.nvim_win_call(winid, function()
		if vim.wo.diff then
			local side = vim.w.diff_side or ""
			-- plain concat: `%%` escaping in string.format is error-prone
			vim.wo.winbar = "%#Title#" .. side .. " %* %t %m%=%#Comment# ]c/[c hunk · za fold · :diffoff %*"
		elseif vim.wo.winbar:find("]c/[c", 1, true) then
			vim.wo.winbar = "" -- ours; clear it
		end
	end)
end

vim.api.nvim_create_autocmd("WinEnter", {
	desc = "Label diff windows in the winbar",
	callback = function()
		setup_diff_winbar()
	end,
})

-- :Gdiff — diff the current file against HEAD: HEAD version in a scratch
-- buffer (vertical split, nofile) with :diffthis in both windows.
-- Key is <leader>gd; diffview.nvim still owns <leader>gv until it's dropped.
vim.keymap.set("n", "<leader>gd", "<cmd>Gdiff<cr>", { desc = "Diff current file vs HEAD" })
vim.api.nvim_create_user_command("Gdiff", function()
	local rel = vim.fn.expand("%:~:.")
	if rel == "" then
		vim.notify("Gdiff: no file name", vim.log.levels.WARN)
		return
	end
	-- git show resolves paths from the repo root, so prepend the cwd prefix.
	local prefix = vim.system({ "git", "rev-parse", "--show-prefix" }, { text = true }):wait()
	if prefix.code ~= 0 then
		vim.notify("Gdiff: not a git repository", vim.log.levels.ERROR)
		return
	end
	local repo_path = prefix.stdout:gsub("%s+$", "") .. rel
	local result = vim.system({ "git", "show", "HEAD:" .. repo_path }, { text = true }):wait()
	if result.code ~= 0 then
		vim.notify("Gdiff: " .. (result.stderr or ""):gsub("%s+$", ""), vim.log.levels.ERROR)
		return
	end

	local orig_ft = vim.bo.filetype
	vim.cmd("vnew")
	vim.bo.buftype = "nofile"
	vim.bo.bufhidden = "wipe"
	vim.bo.filetype = orig_ft
	vim.api.nvim_buf_set_name(0, rel .. " (HEAD)")
	local lines = vim.split(result.stdout, "\n", { plain = true })
	if lines[#lines] == "" then
		lines[#lines] = nil -- git show output ends with a newline
	end
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
	vim.bo.modified = false

	-- Tag the scratch pane as R, the original as L, then label both.
	vim.w.diff_side = "R"
	local scratch_win = vim.api.nvim_get_current_win()
	vim.cmd("diffthis")
	vim.cmd("wincmd p")
	vim.w.diff_side = "L"
	vim.cmd("diffthis")
	setup_diff_winbar(scratch_win)
	setup_diff_winbar()
end, {})
