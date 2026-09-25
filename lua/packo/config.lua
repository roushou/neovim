--- Packo configuration: defaults + optional overrides via setup().

local M = {}

M.defaults = {
	--- Float width in columns.
	width = 86,

	--- Maximum float height. May be a number or a function returning one; the
	--- window still shrinks to the content when there are fewer plugins.
	max_height = function()
		return math.max(6, (vim.o.lines or 24) - 8)
	end,

	--- Width reserved for the plugin name column.
	name_width = 28,

	--- Glyph per row state.
	icons = {
		active = "●",
		inactive = "○",
		drift = "⚠",
		missing = "✗",
		error = "✗",
	},

	--- Highlight group per row state.
	highlights = {
		active = "DiagnosticOk",
		inactive = "Comment",
		drift = "DiagnosticWarn",
		missing = "DiagnosticError",
		error = "DiagnosticError",
	},

	--- Buffer-local keymaps. A value may be a string, a list of strings, or
	--- `false` to unbind.
	keymaps = {
		close = { "q", "<Esc>" },
		detail = { "<CR>" },
		source = { "o" },
		yank_path = { "y" },
		yank_src = { "Y" },
		update = { "u" },
		update_all = { "U" },
		refresh = { "R" },
	},
}

--- @type table Resolved options (defaults merged with user overrides).
M.options = vim.deepcopy(M.defaults)

--- Merge `opts` over the defaults. Lists replace rather than append.
function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
	return M.options
end

return M
