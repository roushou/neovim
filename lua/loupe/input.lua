--- Blocking key loop and key dispatch for loupe.
---
--- Loupe is not a real Vim mode: a `getcharstr` loop reads raw keys and routes
--- them to session operations supplied via `ctx`. This module owns only that
--- layer, keeping the quirky input handling out of the session logic.
---
--- `ctx` fields: `state` (session table), `is_active`, `render`, `close`,
--- `choose`, `reload`, `refresh`, `move`, `page`, `current`, `set_query`,
--- `start_prompt`, `run_action`, `mouse_select`, `yank`.

local tf = require("util.textfield")

local M = {}

--- A key is printable when it isn't a special `<...>` sequence or a control
--- byte. keytrans() renders space and `<` as `<Space>`/`<lt>`, so allow those.
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

--- One key while an inline prompt (rename/delete/create) is active.
local function handle_prompt(ctx, ch, key)
	local S = ctx.state
	local p = S.prompt
	if key == "<CR>" then
		local value, name = p.value, p.action
		S.prompt = nil
		ctx.run_action(name, value)
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

--- One key while the action prefix (`<C-x>`) is showing.
local function handle_prefix(ctx, key)
	local S = ctx.state
	S.prefix = nil
	local item = ctx.current()
	if not item then
		return
	end
	if key == "r" then
		ctx.start_prompt("Rename: ", item.cand.rel, "rename")
	elseif key == "d" then
		ctx.start_prompt("Delete " .. item.cand.rel .. "? [y/N] ", "", "delete")
	elseif key == "a" then
		ctx.start_prompt("Add: ", "", "create")
	elseif key == "y" then
		ctx.yank(item)
	end
end

--- One normal-mode key. Returns true when the picker should quit.
local function handle_normal(ctx, ch, key)
	local S = ctx.state
	if key == "<CR>" then
		return not ctx.choose("edit")
	elseif key == "<Esc>" or key == "<C-C>" then
		ctx.close()
		return true
	elseif key == "<C-S>" then
		return not ctx.choose("split")
	elseif key == "<C-V>" then
		return not ctx.choose("vsplit")
	elseif key == "<C-T>" then
		return not ctx.choose("tab")
	elseif key == "<C-X>" then
		S.prefix = true
	elseif key == "<LeftMouse>" then
		ctx.mouse_select()
	elseif key == "<2-LeftMouse>" then
		if ctx.mouse_select() then
			return not ctx.choose("edit")
		end
	elseif key == "<ScrollWheelUp>" then
		ctx.move(-3)
	elseif key == "<ScrollWheelDown>" then
		ctx.move(3)
	elseif key == "<C-N>" or key == "<Down>" then
		ctx.move(1)
	elseif key == "<C-P>" or key == "<Up>" then
		ctx.move(-1)
	elseif key == "<C-D>" then
		ctx.move(ctx.page())
	elseif key == "<C-U>" then
		ctx.move(-ctx.page())
	elseif key == "<C-O>" then
		S.mode = S.mode == "files" and "dirs" or "files"
		S.query = ""
		S.caret = 0
		S.git = nil
		ctx.reload()
	elseif key == "<C-W>" then
		ctx.set_query(tf.delete_word(S.query, S.caret))
	elseif key == "<BS>" then
		ctx.set_query(tf.backspace(S.query, S.caret))
	elseif key == "<Del>" then
		ctx.set_query(tf.delete(S.query, S.caret))
	elseif key == "<Left>" or key == "<C-B>" then
		S.caret = math.max(0, S.caret - 1)
	elseif key == "<Right>" or key == "<C-F>" then
		S.caret = math.min(tf.len(S.query), S.caret + 1)
	elseif key == "<Home>" or key == "<C-A>" then
		S.caret = 0
	elseif key == "<End>" or key == "<C-E>" then
		S.caret = tf.len(S.query)
	elseif is_printable(ch, key) then
		ctx.set_query(tf.insert(S.query, S.caret, ch))
	end
	return false
end

--- Run the blocking key loop until the picker closes.
function M.run(ctx)
	ctx.render()
	while ctx.is_active() do
		local ch = vim.fn.getcharstr()
		if ch == "" then
			ctx.close()
			return
		end
		local key = vim.fn.keytrans(ch)

		local quit
		if ctx.state.prompt then
			handle_prompt(ctx, ch, key)
		elseif ctx.state.prefix then
			handle_prefix(ctx, key)
		else
			quit = handle_normal(ctx, ch, key)
		end
		if quit then
			return
		end
		ctx.render()
	end
end

return M
