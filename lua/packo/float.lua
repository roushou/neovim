--- Minimal scratch-float helper.
---
--- Self-contained (no dependencies on this config's `ui.*`) so packo can be
--- extracted wholesale.

local M = {}

M.HL = "Normal:NormalFloat,FloatBorder:FloatBorder"

local function scratch(lines)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	if lines then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	end
	return buf
end

--- Open a scratch float. Returns `{ win, buf }`; the buffer has
--- bufhidden=wipe, so closing the window also cleans the buffer.
function M.open(opts)
	local buf = scratch(opts.lines)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = opts.row,
		col = opts.col,
		width = opts.width,
		height = opts.height,
		border = "single",
		title = opts.title,
		title_pos = opts.title_pos,
	})
	vim.wo[win].winhighlight = M.HL
	if opts.cursorline ~= nil then
		vim.wo[win].cursorline = opts.cursorline
	end
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

return M
