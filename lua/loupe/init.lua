--- Loupe: bottom-docked fuzzy file loupe with a full-viewport live preview.
---
--- Public API:
---   require("loupe").setup(opts)
---   require("loupe").open()
---   require("loupe").close()
---   require("loupe").toggle()
---
--- Browsing is side-effect-free: candidate files are read from disk into a
--- reused scratch buffer, never opened as buffers. Only the choose actions
--- (edit/split/vsplit/tab) create a real file buffer.

local config = require("loupe.config")
local backend = require("loupe.backend")
local drawer = require("loupe.drawer")
local preview = require("loupe.preview")
local frecency = require("loupe.frecency")
local git = require("loupe.git")
local action = require("loupe.action")
local tf = require("util.textfield")

local M = {}

local S = nil

local function active()
	return S ~= nil and S.active
end

local function current()
	if not S or S.index < 1 or S.index > #S.matches then
		return nil
	end
	return S.matches[S.index]
end

local function page()
	if S.drawer_win and vim.api.nvim_win_is_valid(S.drawer_win) then
		return math.max(1, vim.api.nvim_win_get_height(S.drawer_win) - 1)
	end
	return 10
end

local function refresh()
	S.matches = backend.match(S.query, S.candidates, config.get().max_results, { root = S.root, mode = S.mode })
	if #S.matches == 0 then
		S.index = 0
	elseif S.index > #S.matches then
		S.index = #S.matches
	end
end

--- Move the selection onto the match with relative path `rel`, if present.
local function focus(rel)
	S.index = 1
	for i, m in ipairs(S.matches) do
		if m.cand.rel == rel then
			S.index = i
			return
		end
	end
end

local function update_preview()
	local cfg = config.get()
	if not cfg.preview.enabled then
		return
	end
	local item = current()
	if item then
		preview.ensure_open(S.drawer_win, S.preview_opts)
		preview.show(item.cand.abs, cfg.preview)
	elseif preview.is_open() then
		preview.clear()
	end
end

local function render()
	-- Update the preview *before* the list redraws, otherwise the redraw paints
	-- the stale preview and it only catches up on the next keypress.
	update_preview()
	drawer.render(S, config.get())
end

local function move(delta)
	local n = #S.matches
	if n == 0 then
		return
	end
	if S.index == 0 then
		S.index = delta > 0 and 1 or n
		return
	end
	S.index = ((S.index - 1 + delta) % n + n) % n + 1
end

--- A key is printable when it isn't a special `<...>` sequence or a control byte.
--- keytrans() renders space and `<` as `<Space>`/`<lt>`, so allow those through.
local function is_printable(ch, key)
	if key == "<Space>" or key == "<lt>" then
		return true
	end
	if key:match("^<.+>$") then
		return false
	end
	local b = ch:byte(1)
	return b ~= nil and b >= 32 and b ~= 127
end

--- Replace the query, reset the selection and refilter (caller redraws).
local function set_query(text, caret)
	S.query = text
	S.caret = caret or tf.len(text)
	S.index = 1
	refresh()
end

local function start_prompt(label, value, name)
	value = value or ""
	S.prompt = { label = label, value = value, action = name, caret = tf.len(value) }
end

--- Run a committed action by name and refresh the view.
local function run_action(name, value)
	local item = current()
	if not item then
		return
	end
	local ctx = { session = S, item = item, root = S.root }
	if name == "rename" then
		local rel = action.rename(ctx, value)
		if rel then
			refresh()
			focus(rel)
		end
	elseif name == "delete" then
		if value:lower() == "y" and action.delete(ctx) then
			refresh()
		end
	elseif name == "create" then
		local rel = action.create(ctx, value)
		if rel then
			S.query = ""
			S.caret = 0
			refresh()
			focus(rel)
		end
	end
	render()
end

--- (Re)enumerate the current root/mode asynchronously and refresh the view.
local function reload()
	if not active() then
		return
	end
	local cfg = config.get()
	S.loaded = false
	S.matches = {}
	S.index = 0
	drawer.render(S, cfg)
	vim.cmd("redraw")

	local root, mode = S.root, S.mode
	backend.list(root, mode, function(cands)
		if not active() or S.root ~= root or S.mode ~= mode then
			return
		end
		if cfg.frecency and mode == "files" then
			cands = frecency.sort(cands)
		end
		S.candidates = cands
		S.loaded = true
		refresh()
		render()
	end)

	if cfg.git and mode == "files" then
		git.status(root, function(map)
			if active() and S.root == root then
				S.git = map
				render()
			end
		end)
	end
end

--- Close the picker and return to the window it was opened from.
function M.close()
	if not active() then
		return
	end
	local origin = S.origin_win
	local guicursor = S.guicursor
	S.active = false
	if S.augroup then
		pcall(vim.api.nvim_del_augroup_by_id, S.augroup)
	end
	preview.close()
	drawer.close(S)
	S = nil
	if guicursor ~= nil then
		pcall(function()
			vim.o.guicursor = guicursor
		end)
	end
	if origin and vim.api.nvim_win_is_valid(origin) then
		vim.api.nvim_set_current_win(origin)
	end
end

--- Commit the current selection and open it for real (or descend into a dir).
--- Returns true when the picker should stay open (directory navigation).
local function choose(kind)
	local item = current()
	if not item then
		return true
	end

	if item.cand.dir then
		S.root = item.cand.abs
		S.mode = "files"
		S.query = ""
		S.caret = 0
		S.git = nil
		reload()
		return true
	end

	local origin = S.origin_win
	M.close()
	if config.get().frecency then
		frecency.record(item.cand.abs)
	end
	local win = origin and vim.api.nvim_win_is_valid(origin) and origin or vim.api.nvim_get_current_win()
	vim.api.nvim_set_current_win(win)
	local path = vim.fn.fnameescape(item.cand.abs)
	if kind == "split" then
		vim.cmd("split " .. path)
	elseif kind == "vsplit" then
		vim.cmd("vsplit " .. path)
	elseif kind == "tab" then
		vim.cmd("tabedit " .. path)
	else
		vim.cmd("edit " .. path)
	end
	return false
end

--- Select the match under the mouse (if the click was in the drawer).
local function mouse_select()
	local mp = vim.fn.getmousepos()
	if mp.winid ~= S.drawer_win or mp.line < 2 then
		return false
	end
	local idx = mp.line - 1
	if idx < 1 or idx > #S.matches then
		return false
	end
	S.index = idx
	return true
end

--- Handle one key while an inline prompt (rename/delete/create) is active.
local function handle_prompt(ch, key)
	local p = S.prompt
	if key == "<CR>" then
		local value, name = p.value, p.action
		S.prompt = nil
		run_action(name, value)
	elseif key == "<Esc>" or key == "<C-C>" then
		S.prompt = nil
	elseif key == "<BS>" then
		p.value, p.caret = tf.backspace(p.value, p.caret)
	elseif key == "<Del>" then
		p.value, p.caret = tf.delete(p.value, p.caret)
	elseif key == "<C-W>" then
		p.value, p.caret = tf.delete_word(p.value, p.caret)
	elseif key == "<C-U>" then
		p.value, p.caret = "", 0
	elseif key == "<Left>" or key == "<C-B>" then
		p.caret = math.max(0, p.caret - 1)
	elseif key == "<Right>" or key == "<C-F>" then
		p.caret = math.min(tf.len(p.value), p.caret + 1)
	elseif key == "<Home>" or key == "<C-A>" then
		p.caret = 0
	elseif key == "<End>" or key == "<C-E>" then
		p.caret = tf.len(p.value)
	elseif is_printable(ch, key) then
		p.value, p.caret = tf.insert(p.value, p.caret, ch)
	end
end

--- Handle one key while the action prefix (`<C-x>`) is showing.
local function handle_prefix(key)
	S.prefix = nil
	local item = current()
	if not item then
		return
	end
	if key == "r" then
		start_prompt("Rename: ", item.cand.rel, "rename")
	elseif key == "d" then
		start_prompt("Delete " .. item.cand.rel .. "? [y/N] ", "", "delete")
	elseif key == "a" then
		start_prompt("Add: ", "", "create")
	elseif key == "y" then
		action.yank({ session = S, item = item, root = S.root })
	end
end

--- Handle one normal-mode key. Returns true when the picker should quit.
local function handle_normal(ch, key)
	if key == "<CR>" then
		return not choose("edit")
	elseif key == "<Esc>" or key == "<C-C>" then
		M.close()
		return true
	elseif key == "<C-S>" then
		return not choose("split")
	elseif key == "<C-V>" then
		return not choose("vsplit")
	elseif key == "<C-T>" then
		return not choose("tab")
	elseif key == "<C-X>" then
		S.prefix = true
	elseif key == "<LeftMouse>" then
		mouse_select()
	elseif key == "<2-LeftMouse>" then
		if mouse_select() then
			return not choose("edit")
		end
	elseif key == "<ScrollWheelUp>" then
		move(-3)
	elseif key == "<ScrollWheelDown>" then
		move(3)
	elseif key == "<C-N>" or key == "<Down>" then
		move(1)
	elseif key == "<C-P>" or key == "<Up>" then
		move(-1)
	elseif key == "<C-D>" then
		move(page())
	elseif key == "<C-U>" then
		move(-page())
	elseif key == "<C-O>" then
		S.mode = S.mode == "files" and "dirs" or "files"
		S.query = ""
		S.caret = 0
		S.git = nil
		reload()
	elseif key == "<C-W>" then
		set_query(tf.delete_word(S.query, S.caret))
	elseif key == "<BS>" then
		set_query(tf.backspace(S.query, S.caret))
	elseif key == "<Del>" then
		set_query(tf.delete(S.query, S.caret))
	elseif key == "<Left>" or key == "<C-B>" then
		S.caret = math.max(0, S.caret - 1)
	elseif key == "<Right>" or key == "<C-F>" then
		S.caret = math.min(tf.len(S.query), S.caret + 1)
	elseif key == "<Home>" or key == "<C-A>" then
		S.caret = 0
	elseif key == "<End>" or key == "<C-E>" then
		S.caret = tf.len(S.query)
	elseif is_printable(ch, key) then
		set_query(tf.insert(S.query, S.caret, ch))
	end
	return false
end

local function loop()
	render()
	while active() do
		local ch = vim.fn.getcharstr()
		if ch == "" then
			M.close()
			return
		end
		local key = vim.fn.keytrans(ch)

		local quit
		if S.prompt then
			handle_prompt(ch, key)
		elseif S.prefix then
			handle_prefix(key)
		else
			quit = handle_normal(ch, key)
		end
		if quit then
			return
		end
		render()
	end
end

--- Open the picker.
function M.open()
	if active() then
		return
	end
	local cfg = config.get()
	local origin = vim.api.nvim_get_current_win()

	S = {
		active = true,
		loaded = false,
		origin_win = origin,
		root = cfg.root(),
		mode = cfg.mode or "files",
		candidates = {},
		query = "",
		caret = 0,
		matches = {},
		index = 0,
		git = nil,
		prompt = nil,
		prefix = false,
		-- captured before the drawer exists, so window-local options are the
		-- user's normal values (drawer turns number/signcolumn off)
		preview_opts = {
			number = vim.wo[origin].number,
			relativenumber = vim.wo[origin].relativenumber,
			signcolumn = vim.wo[origin].signcolumn,
			wrap = vim.wo[origin].wrap,
			linebreak = vim.wo[origin].linebreak,
			list = vim.wo[origin].list,
		},
	}

	local height = type(cfg.height) == "function" and cfg.height() or cfg.height
	local d = drawer.open(height)
	S.drawer_win, S.list_buf = d.win, d.buf
	-- hide the real cursor and draw a caret in the prompt instead
	S.guicursor = vim.o.guicursor
	vim.o.guicursor = "a:LoupeCursor"

	S.augroup = vim.api.nvim_create_augroup("LoupeSession", { clear = true })
	vim.api.nvim_create_autocmd("VimResized", {
		group = S.augroup,
		callback = function()
			if active() then
				preview.resize(S.drawer_win)
				drawer.render(S, config.get())
			end
		end,
	})

	reload()
	loop()
end

--- Toggle the picker.
function M.toggle()
	if active() then
		M.close()
	else
		M.open()
	end
end

--- Configure the picker.
function M.setup(opts)
	config.setup(opts)
end

--- Whether the picker is open.
function M.is_active()
	return active()
end

return M
