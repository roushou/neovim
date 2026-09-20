# Neovim

My personal Neovim configuration. Plugin management uses the built-in
`vim.pack`, LSP servers are declared as data-only files, and the rest is
hand-rolled: a source-based fuzzy finder (**Loupe**), statusline, tabline,
formatter, and a handful of quality-of-life helpers.

![Editor with Kanagawa colorscheme showing a Rust file with custom statusline and buffer tabline](https://github.com/user-attachments/assets/25e34511-4c41-41bd-96cd-e6eb477e057e)

<details>
<summary>More screenshots</summary>

**Lazygit**

![Lazygit floating terminal inside Neovim](https://github.com/user-attachments/assets/bf47d49c-e568-4a36-99b8-8e442f6c8afa)

**Custom LSP info**

![Custom :LspInfo overview window listing attached LSP clients](https://github.com/user-attachments/assets/9c7394cc-cd55-4c97-8ac3-3a7e31d0b725)

</details>

## Highlights

- **Loupe** — the single fuzzy finder: bottom-docked with a full-viewport live
  preview and pluggable sources (files, directories, buffers, recent, changed,
  live grep, workspace/document symbols, diagnostics).
- **Declarative LSP** — one data-only file per server in `lsp/`, registered
  automatically; shared capabilities live in `lua/lsp/setup.lua`.
- **Built-in plugin management** — declared with `vim.pack.add()` and pinned in
  `nvim-pack-lock.json`; no bootstrapping plugin.
- **Hand-rolled UI** — statusline, buffer tabline, diagnostics float, and a
  keymap-reveal helper rather than a full distribution.

## Requirements

- Neovim **≥ 0.12** — uses `vim.pack`, `vim.lsp.config`, and the `lsp/` config dir
- A [Nerd Font](https://www.nerdfonts.com/) for file icons and glyphs
- `git` and `lazygit`
- `fd` and `rg` (ripgrep) for Loupe's file and content search

LSP servers are **not** bundled. Install the ones you need (`lua-language-server`,
`gopls`, `basedpyright-langserver`, …) and make sure they are on your `$PATH`.

## Install

```sh
git clone https://github.com/roushou/neovim.git ~/.config/nvim
nvim
```

Plugins are declared in [`lua/plugins/init.lua`](./lua/plugins/init.lua) with the
built-in `vim.pack.add()` and pinned in
[`nvim-pack-lock.json`](./nvim-pack-lock.json). Run `:vim.pack.update()` to
update them.

## Keymaps

`<leader>` is <kbd>Space</kbd>. This is a selection; the full set lives in
[`lua/keymaps.lua`](./lua/keymaps.lua) and the `after/plugin/` configs.

### Files & search

| Key          | Action                           |
| ------------ | -------------------------------- |
| `<C-p>`      | Loupe — fuzzy finder (see below) |
| `<leader>fw` | Live grep (Loupe)          |
| `<C-n>`      | Toggle file explorer (neo-tree)  |

### Buffers & windows

| Key                             | Action                 |
| ------------------------------- | ---------------------- |
| `<C-h>` `<C-j>` `<C-k>` `<C-l>` | Move between windows   |
| `H` / `L`                       | Previous / next buffer |
| `<leader>x`                     | Close buffer           |
| `<leader>w` / `<leader>q`       | Save / quit            |

### LSP & diagnostics

| Key                         | Action                           |
| --------------------------- | -------------------------------- |
| `<leader>li`                | LSP info                         |
| `<leader>ss`                | Document symbols (Loupe)         |
| `<leader>sw`                | Workspace symbols (Loupe)        |
| `gd`                        | LSP definitions (Trouble)        |
| `<leader>tt`                | Toggle Trouble                   |
| `<leader>td` / `<leader>tw` | Document / workspace diagnostics |
| `<leader>tq` / `<leader>tl` | Quickfix / location list         |
| `[c`                        | Go to Treesitter context         |

### Git

| Key          | Action               |
| ------------ | -------------------- |
| `<leader>gg` | LazyGit              |
| `<leader>gv` | Toggle Diffview      |
| `g[` / `g]`  | Previous / next hunk |
| `<leader>gp` | Preview hunk inline  |
| `<leader>gd` | Diff this            |

### Editing

| Key                                | Action                 |
| ---------------------------------- | ---------------------- |
| `jj` / `jk` (insert)               | Escape                 |
| `j` / `k`                          | Soft down / up         |
| `<` / `>` (visual)                 | Indent, keep selection |
| `<leader>y` / `<leader>p` (visual) | Yank / paste clipboard |

## Loupe

Loupe (`<C-p>`) is a bottom-docked fuzzy finder with a full-viewport live
preview, and the configuration's only picker — it handles files, content search,
symbols, and diagnostics. It is **source-based**: the source menu changes _what_
is being searched, while matching, previewing, and actions stay the same.
Browsing never opens a file buffer — files are read into a scratch buffer, and
only the choose actions create real buffers.

Public API: `require("loupe").open({ source = "files" })`, `.close()`,
`.toggle()`, `.setup(opts)`.

### Sources

Open the source menu with `<C-o>`.

| Key | Source            | Backend             | Notes                                          |
| --- | ----------------- | ------------------- | ---------------------------------------------- |
| `f` | Files             | `fd` → `rg` → `git` | Project files, gitignore-aware                 |
| `d` | Directories       | `fd`                | `<CR>` descends into the directory             |
| `b` | Buffers           | builtin             | Reuses the loaded buffer, unsaved edits intact |
| `r` | Recent            | frecency store      | Most-frequently / recently opened              |
| `c` | Changed           | `git status`        | Staged, unstaged, and untracked                |
| `g` | Grep              | `rg` → `git grep`   | Live content search                            |
| `s` | Workspace symbols | LSP                 | `workspace/symbol`                             |
| `t` | Document symbols  | LSP                 | Symbols in the current buffer                  |
| `e` | Diagnostics       | builtin             | Across all open documents                      |

`grep` and `symbols` are **live**: each keystroke re-queries the backend
(debounced), and the preview jumps to the match. Choosing a symbol or diagnostic
jumps to its location in the buffer.

### Browsing

| Key                                  | Action                                                 |
| ------------------------------------ | ------------------------------------------------------ |
| `<CR>`                               | Open                                                   |
| `<C-s>` / `<C-v>` / `<C-t>`          | Open in split / vsplit / tab                           |
| `<C-o>`                              | Source menu                                            |
| `<C-x>`                              | Action menu (see below)                                |
| `<C-r>`                              | Jump back to the project root                          |
| `<Tab>`                              | Mark entry (marks feed `quickfix`)                     |
| `<C-p>` `<Up>` / `<C-n>` `<Down>`    | Move up / down                                         |
| `<C-d>` / `<C-u>`                    | Page down / up                                         |
| `<Left>` `<C-b>` / `<Right>` `<C-f>` | Move the query caret                                   |
| `<Home>` `<C-a>` / `<End>` `<C-e>`   | Jump to start / end of the query                       |
| `<BS>` / `<Del>` / `<C-w>`           | Delete character / word                                |
| `<Esc>` / `<C-c>`                    | Close                                                  |
| Mouse                                | Click to select, double-click to open, wheel to scroll |

<kbd>Backspace</kbd> on an empty query walks **up one directory**.

### Actions

Open the action menu with `<C-x>`, then:

| Key | Action                                                        |
| --- | ------------------------------------------------------------- |
| `r` | Rename / move (the target may point into another directory)   |
| `d` | Delete (to the OS trash; falls back to unlink for files)      |
| `a` | Add a file — end with `/` to create a directory               |
| `c` | Duplicate                                                     |
| `y` | Yank absolute path                                            |
| `Y` | Yank relative path                                            |
| `n` | Yank filename                                                 |
| `D` | Yank parent directory                                         |
| `o` | Open with the OS default handler                              |
| `q` | Send marked entries (or the current one) to the quickfix list |

### Configuration

Every keybinding is data and can be overridden; set a value to `false` to
unbind. See [`lua/loupe/config.lua`](./lua/loupe/config.lua) for the full set of
actions and options.

```lua
require("loupe").setup({
	default_source = "files",
	trash = true,          -- delete via the OS trash when available
	frecency = true,       -- order the empty-query list by use
	git = true,            -- show git status markers
	backends = {
		files = { "fd", "rg", "git" },
		grep = { "rg", "git" },
	},
	mappings = {
		browse = { ["<CR>"] = "split" },
		menu = { ["m"] = "rename" },
		sources = { ["t"] = "changed" },
	},
})
```

## LSP

Servers live in [`lsp/`](./lsp) as data-only files — one per server. They are
registered and enabled automatically on startup.

### Adding a server

Drop in a file and restart:

```lua
-- lsp/gopls.lua
return {
	cmd = { "gopls" },
	filetypes = { "go", "gomod", "gowork" },
	root_markers = { "go.mod", ".git" },
}
```

Shared defaults (completion capabilities, etc.) live in
[`lua/lsp/setup.lua`](./lua/lsp/setup.lua). Set `enabled = false` in a server
file to keep it loaded but inactive.

## Layout

```
.
├── init.lua                 module wiring
├── nvim-pack-lock.json      pinned plugin revisions
├── after/plugin/            per-plugin setup (blink, gitsigns, kanagawa, neo-tree, …)
├── lsp/                     declarative server configs, one file per server
├── tests/                   headless unit tests
└── lua/
    ├── keymaps.lua          global keymaps
    ├── settings.lua         options
    ├── plugins/             vim.pack declarations + Treesitter
    ├── lsp/                 loader, shared defaults, keymaps, features
    ├── loupe/               the fuzzy finder
    │   ├── backend/         enumeration/search backends (fd, rg, git, nvim, lsp)
    │   └── source/          picker modes (files, dirs, buffers, recent, changed, grep, symbols, doc symbols, diagnostics)
    ├── ui/                  theme, msg, surface, float, highlights, status, buffer/window helpers
    └── util/                process wrapper, file read, text field, debounce
```

## Health & tests

`:checkhealth loupe` reports external tools (`fd`/`rg`/`git`), the resolved
enumeration backends and matcher, and the project root.

The pure unit tests need no plugins and run headlessly (also in CI):

```sh
nvim --headless -u tests/minimal_init.lua -l tests/run.lua
```

## License

[MIT](./LICENSE)
