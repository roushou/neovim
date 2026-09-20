--- Message routing (0.12 `vim._core.ui2`) and notification helpers.
---
--- `setup()` (call once at startup) routes vim.notify — nvim_echo with
--- echomsg/echoerr/info/warn/error kinds — and LSP progress to the ephemeral
--- msg window instead of the cmdline, and repositions that window. Real errors
--- (emsg/lua_error) are not listed, so they stay in the cmdline.
---
--- The `info`/`warn`/`error` helpers and `scoped()` factory standardize
--- notifications across the config.

local util = require("util")

local M = {}

--- Enable ui2 message routing. Idempotent.
function M.setup()
	if M._enabled then
		return
	end
	M._enabled = true

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
		group = util.augroup("ui_msg"),
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

	-- The msg window is anchored above the statusline by default; move it to
	-- the top-right corner and cap its width at half the screen. set_pos runs
	-- on every show/resize, so wrap it.
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
end

--- Notify at `level` (default INFO) with optional |vim.notify()| `opts`.
function M.notify(msg, level, opts)
	vim.notify(msg, level or vim.log.levels.INFO, opts)
end

function M.info(msg, opts)
	vim.notify(msg, vim.log.levels.INFO, opts)
end

function M.warn(msg, opts)
	vim.notify(msg, vim.log.levels.WARN, opts)
end

function M.error(msg, opts)
	vim.notify(msg, vim.log.levels.ERROR, opts)
end

--- A notifier bound to a `scope` prefix, e.g. `local notify = msg.scoped("loupe")`:
--- `notify("hi")`, `notify.warn("careful")`, `notify.error("nope")`, and the
--- legacy `notify("hi", vim.log.levels.WARN)` form.
function M.scoped(scope)
	local prefix = scope .. ": "
	local api = {}
	function api.info(m, opts)
		vim.notify(prefix .. m, vim.log.levels.INFO, opts)
	end
	function api.warn(m, opts)
		vim.notify(prefix .. m, vim.log.levels.WARN, opts)
	end
	function api.error(m, opts)
		vim.notify(prefix .. m, vim.log.levels.ERROR, opts)
	end
	return setmetatable(api, {
		__call = function(_, m, level, opts)
			vim.notify(prefix .. m, level or vim.log.levels.INFO, opts)
		end,
	})
end

return M
