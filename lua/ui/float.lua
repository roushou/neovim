--- Scratch-float window helpers.
---
--- One idiom for the float windows used across the config: an unlisted
--- scratch buffer with bufhidden=wipe, a border/title, and the standard
--- `Normal:NormalFloat,FloatBorder:FloatBorder` window highlight.

local M = {}

M.HL = "Normal:NormalFloat,FloatBorder:FloatBorder"

--- Open a scratch float. Returns a state table `{ win, buf }`; the buffer has
--- bufhidden=wipe, so closing the window (or M.close) also cleans the buffer.
--- `opts` is an nvim_open_win config plus { title, title_pos, border, noautocmd,
--- winhighlight }.
function M.open(opts)
	opts = opts or {}
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	local win = vim.api.nvim_open_win(buf, true, {
		relative = opts.relative or "editor",
		anchor = opts.anchor,
		row = opts.row or 0,
		col = opts.col or 0,
		width = opts.width,
		height = opts.height,
		border = opts.border or "single",
		title = opts.title,
		title_pos = opts.title_pos,
		zindex = opts.zindex,
		noautocmd = opts.noautocmd,
	})
	vim.wo[win].winhighlight = opts.winhighlight or M.HL
	return { win = win, buf = buf }
end

--- Whether a float state (as returned by M.open) is still open.
function M.is_open(state)
	return state ~= nil and state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

--- Close a float state. bufhidden=wipe cleans the buffer.
function M.close(state)
	if M.is_open(state) then
		vim.api.nvim_win_close(state.win, true)
	end
end

--- Top-left row/col to center a float of the given size in the editor.
function M.center(width, height)
	return {
		row = math.max(0, math.floor(((vim.o.lines or 24) - height) / 2)),
		col = math.max(0, math.floor(((vim.o.columns or 80) - width) / 2)),
	}
end

--- Set the buffer lines of a float (nil clears it).
function M.set_lines(state, lines)
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines or {})
end

return M
