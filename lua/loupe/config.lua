--- Loupe configuration: defaults + optional user overrides via setup().

local M = {}

M.defaults = {
	--- Drawer height in lines. May be a number or a function returning one.
	height = function()
		return math.max(8, math.floor(vim.o.lines * 0.33))
	end,

	--- Cap on ranked results rendered (and previewed).
	max_results = 200,

	--- Initial listing mode: "files" or "dirs".
	mode = "files",

	--- Project root resolver. Prefers a VCS root, then common project
	--- markers, then the current working directory.
	root = function()
		local root = vim.fs.root(0, { ".git", ".hg", ".svn", ".jj" })
		if root then
			return root
		end
		root = vim.fs.root(0, { "Cargo.toml", "package.json", "go.mod", "pyproject.toml", ".luarc.json" })
		return root or vim.uv.cwd() or vim.fn.getcwd()
	end,

	--- Backend id. Only "ripgrep" (built-in CLI + matchfuzzypos) exists so far.
	backend = "ripgrep",

	--- Preview options.
	preview = {
		enabled = true,
		--- Read at most this many lines into the preview buffer.
		max_lines = 2000,
	},

	--- Show a per-filetype glyph before each entry.
	icons = true,

	--- Show git status markers (async `git status`) next to files.
	git = true,

	--- Order the empty-query list by frecency (recently/frequently opened).
	frecency = true,

	--- Prompt prefix rendered before the query.
	prompt = "> ",

	--- Caret drawn at the end of the (empty or action) prompt input.
	prompt_caret = "▏",
}

M.values = nil

--- Lazily build the effective config (defaults, or defaults merged by setup()).
function M.get()
	if not M.values then
		M.values = vim.tbl_deep_extend("force", {}, M.defaults)
	end
	return M.values
end

--- Merge user options over the defaults.
function M.setup(opts)
	M.values = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
	return M.values
end

return M
