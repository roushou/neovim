-- ui2: 0.12's core message + cmdline redesign (experimental).
-- Routes vim.notify (nvim_echo -> echomsg/echoerr kinds) and LSP progress to
-- the ephemeral msg window (4s timeout) instead of the cmdline. Real errors
-- (emsg/lua_error) are not listed, so they stay in the cmdline.
require("vim._core.ui2").enable({
	msg = {
		targets = {
			echomsg = "msg",
			echoerr = "msg",
			info = "msg",
			warn = "msg",
			error = "msg",
			progress = "msg",
		},
	},
})

-- LSP $/progress -> progress-kind message, so startup/indexing surfaces in
-- the msg window (see |LspProgress|).
vim.api.nvim_create_autocmd("LspProgress", {
	callback = function(ev)
		local value = ev.data.params.value
		vim.api.nvim_echo({ { value.message or "done" } }, false, {
			id = "lsp." .. ev.data.params.token,
			kind = "progress",
			source = "vim.lsp",
			title = value.title,
			status = value.kind ~= "end" and "running" or "success",
			percent = value.percentage,
		})
	end,
})

-- The msg window is anchored above the statusline by default; move it to the
-- top-right corner and cap its width at half the screen. set_pos runs on every
-- show/resize, so wrap it.
local ui2 = require("vim._core.ui2")
local messages = require("vim._core.ui2.messages")
local set_pos = messages.set_pos
messages.set_pos = function(tgt)
	set_pos(tgt)
	local win = ui2.wins.msg
	if win ~= -1 and vim.api.nvim_win_is_valid(win) then
		local cfg = vim.api.nvim_win_get_config(win)
		if not cfg.hide then
			local cap = math.floor(vim.o.columns / 2)
			messages.msg.width = math.min(messages.msg.width or 1, cap)
			if (cfg.width or 1) > cap then
				cfg.width = cap
			end
			cfg.relative = "editor"
			cfg.anchor = "NE"
			cfg.row = 0
			cfg.col = vim.o.columns
			pcall(vim.api.nvim_win_set_config, win, cfg)
		end
	end
end
