-- Initialization order is explicit here: each step is a plain declaration or a
-- `setup()` call, rather than a require-time side effect. Keep it in order.

-- 1. Options and plugin declarations (must precede anything requiring a plugin).
require("settings")
require("plugins")

-- 2. Theme + message routing.
require("ui.theme")
require("ui.msg").setup()

-- 3. Treesitter — before the colorscheme (loaded from after/plugin/) so
--    kanagawa can link its highlight groups.
require("plugins.treesitter").setup()

-- 4. LSP core and features.
require("lsp").setup()

-- 5. Global keymaps and editor features.
require("keymaps").setup()
require("filetypes").setup()
require("builtins").setup()
require("twin").setup()
require("format").attach()

-- 6. UI surfaces, diagnostic float behaviour, and the plugin dashboard.
require("statusline").setup()
require("tabline").setup()
require("ui.diag_float").setup()
require("packo").setup()

-- 7. Keymap reveal (installs buffer-local triggers).
require("keyd").setup()
