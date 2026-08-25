--- Custom buffer tabline (own bufferline.nvim replacement).
---
--- Renders listed buffers in the global tabline: file icon (mini.icons) +
--- name + modified marker per buffer. The current buffer is a filled accent
--- chip (TablineActive + tail), inactive ones use the native TabLine group.
--- Left-click switches buffer, middle-click closes it. H/L cycle (mapped in
--- keymaps.lua).
---
--- Same idiom as after/plugin/statusline.lua: a `%{%v:lua...%}` expression
--- re-evaluated on every redraw, plus theme colors derived on load and on
--- |ColorScheme|.

local M = {}

-- Show at most this many buffers; a window slides around the current one.
local MAX_VISIBLE = 15

-- Space padding inside each buffer segment, around the label.
local PADDING = 2

-- active-buffer chip colors (same derive pattern as the statusline)
local palette = {}

local function setup_hl()
	local function fg(name)
		return vim.api.nvim_get_hl(0, { name = name }).fg
	end
	local function bg(name)
		return vim.api.nvim_get_hl(0, { name = name }).bg
	end
	palette.bg = bg("StatusLine") or bg("Normal") or 0x16161d
	palette.accent = fg("Directory") or fg("Function") or palette.bg
	vim.api.nvim_set_hl(0, "TablineActive", { fg = palette.bg, bg = palette.accent, bold = true })
	vim.api.nvim_set_hl(0, "TablineActiveTail", { fg = palette.accent })
end
setup_hl()
vim.api.nvim_create_autocmd("ColorScheme", { callback = setup_hl })

local function listed_buffers()
	local buffers = {}
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.fn.buflisted(b) == 1 then
			buffers[#buffers + 1] = b
		end
	end
	return buffers
end

local function current_buffer()
	-- g:actual_curbuf is a STRING (set during statusline evaluation);
	-- convert before comparing against bufnr numbers.
	local b = vim.g.actual_curbuf
	return (b and tonumber(b)) or vim.api.nvim_get_current_buf()
end

local function segment_label(b)
	local path = vim.api.nvim_buf_get_name(b)
	local name = path ~= "" and vim.fn.fnamemodify(path, ":t") or "[No Name]"
	local icon = ""
	if path ~= "" then
		local ic = require("mini.icons").get("file", path)
		icon = (ic and ic .. " ") or ""
	end
	local modified = vim.bo[b].modified and " ●" or ""
	-- escape literal % (buffer names) so they aren't parsed as format items
	return (icon .. name .. modified):gsub("%%", "%%%%")
end

-- Current buffer: filled accent chip + tail; clickable via minwid = bufnr.
local function active_segment(b)
	local pad = (" "):rep(PADDING)
	return string.format(
		"%%#TablineActive#%%%d@TablineClick@%s%s%s%%X%%#TablineActiveTail#▍%%#TabLineFill# ",
		b,
		pad,
		segment_label(b),
		pad
	)
end

local function inactive_segment(b)
	local pad = (" "):rep(PADDING)
	return string.format("%%#TabLine#%%%d@TablineClick@%s%s%s%%X%%#TabLineFill# ", b, pad, segment_label(b), pad)
end

--- Build the tabline format string (re-evaluated on every redraw).
function M.render()
	local buffers = listed_buffers()
	if #buffers == 0 then
		return "%#TabLineFill#%*"
	end
	local cur = current_buffer()
	local cur_idx
	for i, b in ipairs(buffers) do
		if b == cur then
			cur_idx = i
		end
	end

	-- sliding window around the current buffer when there are many
	local first, last = 1, #buffers
	if #buffers > MAX_VISIBLE then
		first = math.max(1, (cur_idx or 1) - math.floor(MAX_VISIBLE / 2))
		last = math.min(#buffers, first + MAX_VISIBLE - 1)
		first = math.max(1, last - MAX_VISIBLE + 1)
	end

	local parts = { "%#TabLineFill#" }
	if first > 1 then
		parts[#parts + 1] = "%#Comment#…%#TabLineFill# "
	end
	for i = first, last do
		if buffers[i] == cur then
			parts[#parts + 1] = active_segment(buffers[i])
		else
			parts[#parts + 1] = inactive_segment(buffers[i])
		end
	end
	if last < #buffers then
		parts[#parts + 1] = "%#Comment#…%#TabLineFill# "
	end
	return table.concat(parts)
end

--- Click handler: left = switch, middle = close (refuses modified buffers).
function M.click(bufnr, _, button)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	if button == "l" then
		vim.cmd.buffer(bufnr)
	elseif button == "m" then
		if vim.bo[bufnr].modified then
			vim.notify("Buffer modified", vim.log.levels.WARN)
		elseif vim.fn.buflisted(bufnr) == 1 then
			vim.api.nvim_buf_delete(bufnr, {})
		end
	end
end

--- Cycle to the next/previous listed buffer (H/L).
function M.cycle(dir)
	local buffers = listed_buffers()
	if #buffers == 0 then
		return
	end
	local cur = vim.api.nvim_get_current_buf()
	local idx
	for i, b in ipairs(buffers) do
		if b == cur then
			idx = i
			break
		end
	end
	local next_idx
	if idx then
		next_idx = ((idx - 1 + dir) % #buffers) + 1
	else
		next_idx = dir > 0 and 1 or #buffers
	end
	vim.cmd.buffer(buffers[next_idx])
end

-- globals referenced by the 'tabline' expression and click labels
_G.TablineRender = M.render
_G.TablineClick = M.click

vim.o.showtabline = 2
vim.o.tabline = "%{%v:lua.TablineRender()%}"

-- redraw when the buffer list / names / modified state can change
vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufEnter", "BufWipeout", "BufFilePost" }, {
	group = vim.api.nvim_create_augroup("tabline_redraw", { clear = true }),
	callback = function()
		vim.cmd("redrawtabline")
	end,
})

return M
