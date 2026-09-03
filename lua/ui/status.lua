--- Statusline / tabline / winbar string helpers.
---
--- All three surfaces share the `%#Group#text%*` segment idiom and the `%`
--- escaping gotcha (literal % must be doubled, so plain concat is safer than
--- string.format).

local M = {}

--- Escape literal % for use in a statusline/tabline/winbar string.
function M.escape(text)
	return (text:gsub("%%", "%%%%"))
end

--- A `%#Group#text%*` segment.
function M.segment(group, text)
	return "%#" .. group .. "#" .. text .. "%*"
end

--- A clickable segment. Statusline callbacks use `%@Func@`; tabline callbacks
--- use `%{minwid}@Func@` (pass opts.minwid). The text between the item and
--- `%X` is what gets clicked.
function M.click(group, text, func, opts)
	opts = opts or {}
	local item = opts.minwid ~= nil and ("%%%d@%s@"):format(opts.minwid, func) or "%@" .. func .. "@"
	return "%#" .. group .. "#" .. item .. text .. "%X%*"
end

return M
