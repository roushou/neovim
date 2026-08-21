-- Native tag editing helpers: rename, close-on->, close-on-</.
--
-- Rename via vim.lsp.linked_editing_range where the server supports it
-- (svelte/astro); treesitter fallback on InsertLeave otherwise (jsx/tsx, html).
-- Needs the parsers in lua/plugins/treesitter.lua ensure_installed.

local api, ts = vim.api, vim.treesitter

-- Native, live paired-tag rename where the language server supports it.
vim.lsp.linked_editing_range.enable(true)

-- filetype -> treesitter node types: element / start tag / start tag name /
-- end tag / end tag name (mirrors nvim-ts-autotag's per-grammar config).
local FAMILY = {
	html = {
		element = "element",
		start = "start_tag",
		start_name = "tag_name",
		["end"] = "end_tag",
		end_name = "tag_name",
	},
	xml = { element = "element", start = "STag", start_name = "tag_name", ["end"] = "ETag", end_name = "tag_name" },
	tsx = {
		element = "jsx_element",
		start = "jsx_opening_element",
		start_name = { "identifier", "jsx_identifier", "nested_identifier", "tag_name", "member_expression" },
		["end"] = "jsx_closing_element",
		end_name = { "identifier", "tag_name" },
	},
	heex = {
		element = "element",
		start = "start_component",
		start_name = "component_name",
		["end"] = "end_component",
		end_name = "component_name",
	},
	glimmer = {
		element = "element_node",
		start = "element_node_start",
		start_name = "tag_name",
		["end"] = "element_node_end",
		end_name = "tag_name",
	},
	templ = {
		element = "element",
		start = "tag_start",
		start_name = { "element_identifier", "name" },
		["end"] = "tag_end",
		end_name = { "element_identifier", "name" },
	},
	rust = {
		element = "element_node",
		start = "open_tag",
		start_name = "node_identifier",
		["end"] = "close_tag",
		end_name = { "close_tag", "node_identifier" },
	},
}

-- filetypes per family (nvim-ts-autotag's alias map)
local FILETYPES = {
	html = {
		"html",
		"htmldjango",
		"vue",
		"svelte",
		"astro",
		"eruby",
		"liquid",
		"twig",
		"blade",
		"php",
		"dot",
		"vento",
		"htmlangular",
		"mdx",
		"markdown",
	},
	xml = { "xml" },
	tsx = { "javascriptreact", "typescriptreact", "javascript", "typescript", "rescript" },
	heex = { "heex", "elixir" },
	glimmer = { "handlebars", "glimmer", "hbs" },
	templ = { "templ" },
	rust = { "rust" },
}

local FT2FAMILY = {}
for fam, fts in pairs(FILETYPES) do
	for _, ft in ipairs(fts) do
		FT2FAMILY[ft] = fam
	end
end

-- HTML void elements never get a closing tag.
local VOID = {
	area = true,
	base = true,
	br = true,
	col = true,
	command = true,
	embed = true,
	hr = true,
	img = true,
	slot = true,
	input = true,
	keygen = true,
	link = true,
	meta = true,
	param = true,
	source = true,
	track = true,
	wbr = true,
	menuitem = true,
}

local function contains(list, value)
	if type(list) == "table" then
		for _, v in ipairs(list) do
			if v == value then
				return true
			end
		end
		return false
	end
	return list == value
end

local function cfg_for(buf)
	local fam = FT2FAMILY[vim.bo[buf].filetype]
	return fam and FAMILY[fam]
end

local function climb(node, pred)
	while node do
		if pred(node) then
			return node
		end
		node = node:parent()
	end
end

local function child_of_type(node, types)
	for child in node:iter_children() do
		if contains(types, child:type()) then
			return child
		end
	end
end

local function tag_name_node(tag, types)
	return child_of_type(tag, types)
end

-- tree-sitter-html parses a mismatched end tag (while renaming) as
-- `erroneous_end_tag` instead of `end_tag`; treat it as an end tag.
local function has_end_tag(element, cfg)
	return child_of_type(element, cfg["end"]) ~= nil or child_of_type(element, "erroneous_end_tag") ~= nil
end

local function end_name_node(end_tag, cfg)
	local name = child_of_type(end_tag, cfg.end_name)
	return name or child_of_type(end_tag, "erroneous_end_tag_name")
end

local function node_text(node, buf)
	if not node then
		return nil
	end
	-- 0.12 returns a plain string (0.11 returned a list of lines)
	return vim.treesitter.get_node_text(node, buf)
end

local function prefix_closes_tag(line, col)
	-- `col` is the nvim col (0-based) of the just-typed `>`; cheap guard so
	-- plain `>` (comparisons, arrows, generics) skips the treesitter work.
	-- `<[^<>]*>` also admits the jsx fragment `<>` and void `<br>`.
	local prefix = line:sub(1, col + 1)
	return prefix:match("<[^<>]*%s*>%s*$") ~= nil
end

local function reparse(buf)
	local ok, parser = pcall(vim.treesitter.get_parser, buf)
	if not ok then
		return nil
	end
	parser:parse(true)
	return parser
end

-- Find a start-type node ending exactly at (row-1, after_col). Unclosed
-- tags are often wrapped in an ERROR node whose start tag is a *child*
-- (not ancestor) of the cursor node, so search self, its children, then up.
local function find_start_at(node, buf, row, after_col, cfg)
	local n = node
	while n do
		local sr, sc, er, ec = n:range()
		if contains(cfg.start, n:type()) and er == row - 1 and ec == after_col then
			return n
		end
		for child in n:iter_children() do
			local _, _, cer, cec = child:range()
			if contains(cfg.start, child:type()) and cer == row - 1 and cec == after_col then
				return child
			end
		end
		n = n:parent()
	end
end

-- Insert `</name>` after the `>` that was just typed; keep cursor inside.
local function close_tag(buf, row, after_col)
	local cfg = cfg_for(buf)
	if not cfg then
		return
	end
	local parser = reparse(buf)
	if not parser then
		return
	end
	-- Position right before the insertion point, i.e. ON the `>` we just typed.
	local node = vim.treesitter.get_node({ buf = buf, pos = { row - 1, after_col - 1 } })
	if not node then
		return
	end
	local start = find_start_at(node, buf, row, after_col, cfg)
	if not start then
		return
	end
	-- Fragment (jsx `<>`): complete with `</>`.
	local text = node_text(start, buf)
	if text and text:match("^%s*<%s*>%s*$") then
		api.nvim_buf_set_text(buf, row - 1, after_col, row - 1, after_col, { "</>" })
		return
	end
	-- Self-closing `/>`.
	if text and text:match("/%s*>%s*$") then
		return
	end
	local name = tag_name_node(start, cfg.start_name)
	local ntext = name and node_text(name, buf)
	if not ntext or VOID[ntext] then
		return
	end
	-- Skip only when this tag opens an element already closed with a
	-- *matching* end tag. (The parser can positionally pair a mismatched
	-- end tag, e.g. `<span></Component>` — that still needs closing.)
	local element = climb(node, function(n)
		return n:type() == cfg.element
	end)
	if element then
		local elem_start = child_of_type(element, cfg.start)
		if elem_start == start then
			local etag = child_of_type(element, cfg["end"]) or child_of_type(element, "erroneous_end_tag")
			local ename = etag and end_name_node(etag, cfg)
			local estext = ename and node_text(ename, buf)
			if estext == ntext then
				return
			end
		end
	end
	api.nvim_buf_set_text(buf, row - 1, after_col, row - 1, after_col, { "</" .. ntext .. ">" })
end

-- Complete `</` with the innermost open tag's name. Returns the number of
-- chars inserted (0 when nothing was completed) so the caller can place the
-- cursor.
local function close_slash_tag(buf, row, col)
	local cfg = cfg_for(buf)
	if not cfg then
		return 0
	end
	local parser = reparse(buf)
	if not parser then
		return 0
	end
	-- Position ON the `/` we just typed.
	local node = vim.treesitter.get_node({ buf = buf, pos = { row - 1, col } })
	if not node then
		return
	end
	-- Find the nearest node (self or ancestor) that directly contains a start
	-- tag. For an unclosed tag this is the ERROR wrapper: its start tags are
	-- siblings, and the innermost open one is the LAST one before the cursor.
	local container = climb(node, function(n)
		return child_of_type(n, cfg.start) ~= nil
	end)
	if not container then
		return 0
	end
	if has_end_tag(container, cfg) then
		return 0 -- already closed
	end
	local start, start_text
	for child in container:iter_children() do
		if contains(cfg.start, child:type()) then
			local _, _, er, ec = child:range()
			if er < row - 1 or (er == row - 1 and ec <= col) then
				start = child
				start_text = node_text(child, buf)
			end
		end
	end
	if not start then
		return 0
	end
	if not start_text or not start_text:match(">%s*$") then
		return 0 -- start tag not properly opened yet
	end
	local name = tag_name_node(start, cfg.start_name)
	local ntext = name and node_text(name, buf)
	if not ntext or VOID[ntext] then
		return 0
	end
	api.nvim_buf_set_text(buf, row - 1, col + 1, row - 1, col + 1, { ntext .. ">" })
	return #ntext
end

local function replace_node(node, text, buf)
	local sr, sc, er, ec = node:range()
	api.nvim_buf_set_text(buf, sr, sc, er, ec, { text })
end

-- Treesitter rename fallback for buffers without a linked-editing client.
local function rename_tags(buf)
	if #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/linkedEditingRange" }) > 0 then
		return
	end
	local cfg = cfg_for(buf)
	if not cfg then
		return
	end
	local row, col = unpack(api.nvim_win_get_cursor(0))
	local line = api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
	-- Only when the char before the cursor is a word char (we just edited a name).
	if not line or col < 1 or not line:sub(col, col):match("%w") then
		return
	end
	if not reparse(buf) then
		return
	end
	local node = vim.treesitter.get_node({ buf = buf, pos = { row - 1, col - 1 } })
	if not node then
		return
	end
	local element = climb(node, function(n)
		return n:type() == cfg.element
	end)
	if not element then
		return
	end
	local start_tag = child_of_type(element, cfg.start)
	local end_tag = child_of_type(element, cfg["end"])
	if not end_tag then
		end_tag = child_of_type(element, "erroneous_end_tag")
	end
	if not (start_tag and end_tag) then
		return
	end
	local sname = tag_name_node(start_tag, cfg.start_name)
	local ename = end_name_node(end_tag, cfg)
	if not (sname and ename) then
		return
	end
	local stext, etext = node_text(sname, buf), node_text(ename, buf)
	if not stext or not etext or stext == etext then
		return
	end
	-- Sync the side that wasn't just edited.
	local edited = climb(node, function(n)
		return n == sname or n == ename
	end)
	if edited == sname then
		replace_node(ename, stext, buf)
	elseif edited == ename then
		replace_node(sname, etext, buf)
	end
end

local function attach(buf)
	if vim.b[buf].tagged_attached then
		return
	end
	if not cfg_for(buf) then
		return
	end
	local ok = pcall(vim.treesitter.get_parser, buf)
	if not ok then
		return
	end
	vim.b[buf].tagged_attached = true
	local group = api.nvim_create_augroup("tagged-" .. buf, { clear = true })

	vim.keymap.set("i", ">", function()
		local row, col = unpack(api.nvim_win_get_cursor(0))
		api.nvim_buf_set_text(buf, row - 1, col, row - 1, col, { ">" })
		local line = api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
		if line and prefix_closes_tag(line, col) then
			close_tag(buf, row, col + 1)
		end
		-- Cursor sits right after the `>` (inside the tag) in every case.
		api.nvim_win_set_cursor(0, { row, col + 1 })
	end, { buffer = buf, noremap = true, silent = true })

	vim.keymap.set("i", "/", function()
		local row, col = unpack(api.nvim_win_get_cursor(0))
		api.nvim_buf_set_text(buf, row - 1, col, row - 1, col, { "/" })
		local line = api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
		local inserted = 0
		if line and line:sub(col, col) == "<" then
			inserted = close_slash_tag(buf, row, col)
		end
		-- After `</name>` the cursor is before the `>`; otherwise after the `/`.
		api.nvim_win_set_cursor(0, { row, col + 1 + inserted })
	end, { buffer = buf, noremap = true, silent = true })

	api.nvim_create_autocmd("InsertLeave", {
		group = group,
		buffer = buf,
		callback = function()
			rename_tags(buf)
		end,
	})
end

api.nvim_create_autocmd("FileType", {
	desc = "Enable native tag close/rename helpers",
	callback = function(ev)
		attach(ev.buf)
	end,
})
