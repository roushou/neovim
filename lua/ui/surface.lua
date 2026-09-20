--- Statusline / tabline expression + click registration.
---
--- Both surfaces use `%{%v:lua...%}` expressions and `%@Func@` click labels.
--- A click label must resolve a Vimscript function, so `clickable()` installs a
--- thin shim that forwards to a Lua function.

local M = {}

--- Register `fn` as a global and return the `%{%v:lua.Name()%}` fragment for a
--- 'statusline'/'tabline' option.
function M.expr(name, fn)
	_G[name] = fn
	return "%{%v:lua." .. name .. "()%}"
end

--- Register `fn` as the handler for click labels named `name`.
function M.clickable(name, fn)
	_G[name] = fn
	vim.fn.execute(
		("function! %s(minwid, clicks, button, modifiers) abort\n\treturn v:lua.%s(a:minwid, a:clicks, a:button, a:modifiers)\nendfunction"):format(
			name,
			name
		)
	)
end

return M
