require("neo-tree").setup({
	close_if_last_window = true,
	-- Disable console notifications (vim.notify) from Neo-tree.
	-- Only show ERROR and above; suppress INFO and WARN.
	log_level = "error",
	window = {
		position = "right",
		width = 30,
	},
	filesystem = {
		filtered_items = {
			always_show = {
				".gitignore",
				".env",
				".dev.vars",
				".github",
			},
		},
		follow_current_file = {
			enabled = true,
			leave_dirs_open = true,
		},
	},
	default_component_configs = {
		icon = {
			-- Icons from mini.icons (nvim-web-devicons is not installed).
			-- Mirrors the default provider but reads mini.icons instead.
			provider = function(icon, node)
				if node.type == "file" or node.type == "terminal" then
					local name = node.type == "terminal" and "terminal" or node.name
					local devicon, hl = require("mini.icons").get("file", name)
					icon.text = devicon or icon.text
					icon.highlight = hl or icon.highlight
				end
			end,
		},
	},
})
