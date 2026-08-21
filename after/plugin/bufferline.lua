require("bufferline").setup({
	options = {
		show_buffer_close_icons = false,
		hover = {
			enable = true,
			reveal = { "close" },
		},
		-- Icons from mini.icons (nvim-web-devicons is not installed).
		get_element_icon = function(opts)
			local icons = require("mini.icons")
			if opts.path and opts.path ~= "" then
				local icon, hl = icons.get(opts.directory and "directory" or "file", opts.path)
				if icon then
					return icon, hl
				end
			end
			if opts.filetype and opts.filetype ~= "" then
				local icon, hl = icons.get("filetype", opts.filetype)
				if icon then
					return icon, hl
				end
			end
			return "", nil
		end,
	},
})
