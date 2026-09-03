-- Native statusline: the 0.12 default expression (diagnostics, LSP progress,
-- terminal exit code, busy, ruler) plus a mode chip and info sections
-- (filetype, git branch/diff, search count, recording indicator). Colors are
-- read from the active colorscheme on load and on every |ColorScheme|.
--
-- Layout:
--   [MODE]▌ [filetype] ⎇ git-branch +a ~c -d   %f %m %r ... (0.12 default) ... ●clangd ●rust-analyzer [n/m] ● @q  12,8 45%
--
-- Notes:
-- - The 0.12 default 'statusline' is already an expression; we prepend our
--   left sections and splice our right sections just before the ruler.
-- - `%{%...%}` re-evaluates the function result as a statusline format
--   string, so the `%#Group#`/`%*` items we return take effect.
-- - The LSP section lists clients attached to the active window; clicking it
--   opens the :LspInfo overview (lua/lsp/features/info.lua).

local theme = require("ui.theme")
local status = require("ui.status")

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

-- Read resolved colors from the active colorscheme and (re)build the derived
-- highlight groups. Runs on load and on every |ColorScheme|.
local function refresh()
	palette.bg = theme.bg({ "StatusLine", "Normal" }, 0x16161d)
	palette.fg = theme.fg({ "StatusLine", "Normal" }, 0xdcd7ba)
	for _, entry in pairs(MODE) do
		palette[entry[2]] = theme.fg(entry[2], palette.fg)
	end
	palette.git = theme.fg("DiagnosticHint", palette.fg)
	palette.gitcount = theme.fg("Comment", palette.fg)
	palette.ft = theme.fg("Function", palette.fg)
	palette.search = theme.fg("Constant", palette.fg)
	palette.rec = theme.fg("Error", palette.fg)
	palette.lsp = theme.fg({ "DiagnosticOk", "DiagnosticInfo" }, palette.fg)

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
	vim.api.nvim_set_hl(0, "StatusLineLsp", { fg = palette.lsp })
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
	return status.segment(groups.chip, " " .. name .. " ") .. status.segment(groups.tail, "▌")
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
	local out = status.segment("StatusLineGit", " ⎇ " .. head)
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
		out = out .. " " .. status.segment("StatusLineGitCount", table.concat(counts, " "))
	end
	return out
end

local function ft_section()
	local ft = vim.bo.filetype
	if ft == "" then
		return ""
	end
	return status.segment("StatusLineFiletype", " [" .. ft .. "]")
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
	return status.segment("StatusLineSearch", "[" .. sc.current .. "/" .. sc.total .. "]")
end

local function rec_section()
	if not active() then
		return ""
	end
	local reg = vim.fn.reg_recording()
	if reg == "" then
		return ""
	end
	return status.segment("StatusLineRecording", " ● @" .. reg)
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

-- LSP clients attached to the active window, e.g. `● rust-analyzer ● clangd`.
-- `●` connected, `◐` starting. Click (left) to open the :LspInfo overview.
local LSP_MAX = 30
local function lsp_section()
	if not active() then
		return ""
	end
	local clients = vim.lsp.get_clients({ bufnr = vim.api.nvim_get_current_buf(), _uninitialized = true })
	if #clients == 0 then
		return ""
	end
	local parts = {}
	for _, c in ipairs(clients) do
		parts[#parts + 1] = (c.initialized and "●" or "◐") .. " " .. c.name
	end
	local label = table.concat(parts, " ")
	if #label > LSP_MAX then
		label = label:sub(1, LSP_MAX - 1) .. "…"
	end
	return status.click("StatusLineLsp", label, "StatuslineLspClick")
end

function _G.StatuslineLspClick(...)
	local button = select(3, ...)
	if button ~= "l" then
		return
	end
	vim.schedule(function()
		require("lsp.features.info").open()
	end)
end

function _G.StatuslineRight()
	local parts = {}
	local l = lsp_section()
	if l ~= "" then
		parts[#parts + 1] = l
	end
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

theme.on_colorscheme(refresh)

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
