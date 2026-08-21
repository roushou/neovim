-- Native statusline: the 0.12 default expression (diagnostics, LSP progress,
-- terminal exit code, busy, ruler) plus a mode chip and info sections
-- (filetype, git branch/diff, search count, recording indicator). Colors are
-- read from the active colorscheme on load and on every |ColorScheme|.
--
-- Layout:
--   [MODE]▌ [filetype] ⎇ git-branch +a ~c -d   %f %m %r ... (0.12 default) ... [n/m] ● @q  12,8 45%
--
-- Notes:
-- - The 0.12 default 'statusline' is already an expression; we prepend our
--   left sections and splice our right sections just before the ruler.
-- - `%{%...%}` re-evaluates the function result as a statusline format
--   string, so the `%#Group#`/`%*` items we return take effect.

-- mode -> { label, anchor group, printable name (for hl group names) }
local MODE = {
	n = { "NORMAL", "Directory", "Normal" }, -- blue
	no = { "N·OP", "Directory", "Normal" },
	i = { "INSERT", "String", "Insert" }, -- green
	ic = { "INSERT", "String", "Insert" },
	v = { "VISUAL", "Keyword", "Visual" }, -- purple
	V = { "V·LINE", "Keyword", "Visual" },
	["\22"] = { "V·BLOCK", "Keyword", "Visual" },
	c = { "COMMAND", "PreProc", "Command" }, -- pink
	R = { "REPLACE", "Error", "Replace" }, -- red
	t = { "TERMINAL", "Type", "Terminal" }, -- teal
	s = { "SELECT", "Constant", "Select" }, -- orange
	S = { "S·LINE", "Constant", "Select" },
	["\19"] = { "S·BLOCK", "Constant", "Select" },
	-- "r"* = hit-enter / more prompt
	r = { "PROMPT", "Comment", "Prompt" }, -- dim
}

local palette = {}

-- [mode name] -> chip group, tail group
local GROUPS = {}

local function setup_hl()
	for key, entry in pairs(MODE) do
		local accent = palette[entry[2]]
		local chip = "StatusLineMode" .. entry[3]
		local tail = "StatusLineModeTail" .. entry[3]
		vim.api.nvim_set_hl(0, chip, { fg = palette.bg, bg = accent, bold = true })
		vim.api.nvim_set_hl(0, tail, { fg = accent, bg = palette.bg })
		GROUPS[key] = { chip = chip, tail = tail }
	end
	-- Info sections: plain fg on the StatusLine background.
	vim.api.nvim_set_hl(0, "StatusLineGit", { fg = palette.git })
	vim.api.nvim_set_hl(0, "StatusLineGitCount", { fg = palette.gitcount })
	vim.api.nvim_set_hl(0, "StatusLineFiletype", { fg = palette.ft })
	vim.api.nvim_set_hl(0, "StatusLineSearch", { fg = palette.search })
	vim.api.nvim_set_hl(0, "StatusLineRecording", { fg = palette.rec })
end

-- Read resolved colors from the active colorscheme. Runs on load and on
-- every |ColorScheme|, so a `:colorscheme foo` restyles the statusline.
local function derive()
	local function fg(name)
		return vim.api.nvim_get_hl(0, { name = name }).fg
	end
	local function bg(name)
		return vim.api.nvim_get_hl(0, { name = name }).bg
	end
	palette.bg = bg("StatusLine") or bg("Normal") or 0x16161d
	palette.fg = fg("StatusLine") or fg("Normal") or 0xdcd7ba
	for _, entry in pairs(MODE) do
		palette[entry[2]] = fg(entry[2]) or palette.fg
	end
	palette.git = fg("DiagnosticHint") or palette.fg
	palette.gitcount = fg("Comment") or palette.fg
	palette.ft = fg("Function") or palette.fg
	palette.search = fg("Constant") or palette.fg
	palette.rec = fg("Error") or palette.fg
	setup_hl()
end

local function mode_info()
	local m = vim.fn.mode(1) -- includes submodes (e.g. "ic", "no", "Rv")
	local entry = MODE[m] or MODE[m:sub(1, 1)] or MODE.n
	return entry[1], GROUPS[m] or GROUPS[m:sub(1, 1)] or GROUPS.n
end

-- Only the window that actually has focus (see |stl-%{| for g:actual_curwin).
local function active()
	return vim.api.nvim_get_current_win() == tonumber(vim.g.actual_curwin or -1)
end

-- Return value is re-evaluated as a statusline format string (via %{%...%}).
-- Exposed as globals so the v:lua references in 'statusline' can call them.
function _G.StatuslineMode()
	if not active() then
		return ""
	end
	local name, groups = mode_info()
	-- plain concat: `%%` escaping in string.format would be error-prone
	return "%#" .. groups.chip .. "# " .. name .. " %#" .. groups.tail .. "#▌%*"
end

-- Git branch + per-hunk counts, from gitsigns' per-buffer cache
-- (b:gitsigns_status_dict is maintained by gitsigns itself, so no polling).
-- `⎇` is mini.statusline's branch glyph — swap if your font renders tofu.
local function git_section()
	local d = vim.b.gitsigns_status_dict
	if not d or not d.head then
		return ""
	end
	local head = d.head
	if #head > 24 then
		head = head:sub(1, 11) .. "…"
	end
	local out = "%#StatusLineGit# ⎇ " .. head
	local counts = {}
	if (d.added or 0) > 0 then
		counts[#counts + 1] = "+" .. d.added
	end
	if (d.changed or 0) > 0 then
		counts[#counts + 1] = "~" .. d.changed
	end
	if (d.removed or 0) > 0 then
		counts[#counts + 1] = "-" .. d.removed
	end
	if #counts > 0 then
		out = out .. " %#StatusLineGitCount#" .. table.concat(counts, " ")
	end
	return out
end

local function ft_section()
	local ft = vim.bo.filetype
	if ft == "" then
		return ""
	end
	return "%#StatusLineFiletype# [" .. ft .. "]"
end

-- Search progress, e.g. `[3/42]`. `recompute = false` reads nvim's cached
-- count (updated on every search), so this is free on each redraw.
local function search_section()
	if not active() then
		return ""
	end
	local sc = vim.fn.searchcount({ recompute = false })
	if not sc or not sc.total or sc.total == 0 then
		return ""
	end
	return "%#StatusLineSearch#[" .. sc.current .. "/" .. sc.total .. "]"
end

local function rec_section()
	if not active() then
		return ""
	end
	local reg = vim.fn.reg_recording()
	if reg == "" then
		return ""
	end
	return "%#StatusLineRecording# ● @" .. reg
end

function _G.StatuslineLeft()
	local parts = { _G.StatuslineMode() }
	local ft = ft_section()
	if ft ~= "" then
		parts[#parts + 1] = ft
	end
	local git = git_section()
	if git ~= "" then
		parts[#parts + 1] = git
	end
	local out = table.concat(parts, " ")
	if out == "" then
		return ""
	end
	return out .. " "
end

function _G.StatuslineRight()
	local parts = {}
	local s = search_section()
	if s ~= "" then
		parts[#parts + 1] = s
	end
	local r = rec_section()
	if r ~= "" then
		parts[#parts + 1] = r
	end
	if #parts == 0 then
		return ""
	end
	return " " .. table.concat(parts, " ") .. " "
end

derive()
vim.api.nvim_create_autocmd("ColorScheme", { callback = derive })

-- Mode is now shown in the statusline; hide the legacy "-- INSERT --" message.
vim.o.showmode = false

-- Compose with the 0.12 default: prepend left sections, splice the right
-- sections just before the ruler. If the default ever changes shape (the
-- ruler fragment no longer matches), fall back to appending at the very end.
local default = vim.o.statusline
local RULER = "%{% &ruler ? ( &rulerformat == '' ? '%-14.(%l,%c%V%) %P' : &rulerformat ) : '' %}"
local left = "%{%v:lua.StatuslineLeft()%}"
local right = "%{%v:lua.StatuslineRight()%}"
local start, finish = default:find(RULER, 1, true)
if start then
	vim.o.statusline = left .. default:sub(1, start - 1) .. right .. default:sub(start)
else
	vim.o.statusline = left .. default .. right
end
