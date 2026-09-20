# Neovim

My personal Neovim configuration — built-in plugin management, declarative LSP setup, and a set of hand-rolled features (tabline, statusline, symbol pickers, formatter, keymap reveal).

<img width="1920" height="1170" alt="Editor with Kanagawa colorscheme showing a Rust file with custom statusline and buffer tabline" src="https://github.com/user-attachments/assets/25e34511-4c41-41bd-96cd-e6eb477e057e" />

**Lazygit**

<img width="1920" height="1170" alt="Lazygit floating terminal inside Neovim" src="https://github.com/user-attachments/assets/bf47d49c-e568-4a36-99b8-8e442f6c8afa" />

**Custom LSP info**

<img width="1920" height="1170" alt="Custom :LspInfo overview window listing attached LSP clients" src="https://github.com/user-attachments/assets/9c7394cc-cd55-4c97-8ac3-3a7e31d0b725" />

## Requirements

- Neovim **≥ 0.12** (`vim.pack`, `vim.lsp.config`, `lsp/` config dir)
- A [Nerd Font](https://www.nerdfonts.com/) for file icons and glyphs
- External tools: `git`, `lazygit`, `fd`, `rg` (ripgrep)

LSP servers are **not** bundled — install the ones you need (e.g. `lua-language-server`, `gopls`, `basedpyright-langserver`) and make sure they're on your `$PATH`.

## Setup

```sh
git clone https://github.com/roushou/neovim.git ~/.config/nvim
nvim
```

Plugins are declared in [`lua/plugins/init.lua`](./lua/plugins/init.lua) via the built-in `vim.pack.add()` and pinned in [`nvim-pack-lock.json`](./nvim-pack-lock.json); run `:vim.pack.update()` to update.

## Layout

```
init.lua            entry point: module wiring
nvim-pack-lock.json pinned plugin revisions
after/plugin/       per-plugin config (blink, gitsigns, kanagawa, neo-tree, …)
lua/
├── keymaps.lua     global keymaps
├── settings.lua    options
├── util.lua        map() helper
├── util/           process wrapper (proc)
├── keyd.lua        keymap-reveal helper
├── statusline.lua  statusline
├── tabline.lua     buffer tabline
├── notify.lua      ui2 message routing
├── builtins.lua    undo tree, :Gdiff, yank flash
├── tagged.lua      tag close/rename helpers
├── format.lua      format-on-save via external binaries
├── filetypes.lua   per-filetype defaults (indent, detection)
├── loupe/          bottom fuzzy picker (sources) + full-screen live preview
├── lsp/            LSP core (loader, keys) + features (info, pickers, hints)
├── ui/             UI helpers (theme, float, hl, status, buf, win, preview) + diagnostic float
└── plugins/
    └── treesitter.lua  parsers + textobjects setup
lsp/                declarative server configs — one file per LSP (data only)
tests/              pure headless unit tests
```

### Adding an LSP server

Drop a data-only file into `lsp/`, restart:

```lua
-- lsp/gopls.lua
return {
	cmd = { "gopls" },
	filetypes = { "go", "gomod", "gowork" },
	root_markers = { "go.mod", ".git" },
}
```

It's registered and enabled automatically. Shared defaults (completion capabilities) live in `lua/lsp/setup.lua`; set `enabled = false` in a file to keep it loaded but inactive.

## Keymaps (selection)

| Key           | Action                    |
| ------------- | ------------------------- |
| `<C-p>`       | Find files                |
| `<leader>fw`  | Live grep                 |
| `<C-n>`       | Toggle file explorer      |
| `H` / `L`     | Previous / next buffer    |
| `<leader>x`   | Close buffer              |
| `<leader>li`  | LSP info                  |
| `<leader>ss`  | LSP symbols (document)    |
| `<leader>sw`  | LSP workspace symbols     |
| `<C-h/j/k/l>` | Navigate windows          |

Inside Loupe (`<C-p>`): `<CR>` open, `<C-s>`/`<C-v>`/`<C-t>` open in split/vsplit/tab, `<C-o>` source menu (`f` files, `d` dirs, `b` buffers, `r` recent, `c` changed, `g` live grep, `s` workspace symbols), `<C-x>` action prefix (`r` rename/move, `d` delete to trash, `a` add file (trailing `/` makes a dir), `c` duplicate, `y` yank path, `Y`/`n`/`D` yank relative/name/dir, `o` open externally, `q` send to quickfix), `<Tab>` mark (marks feed quickfix), `<C-r>` jump to project root, `<BS>` on an empty query goes up a directory, `<Left>`/`<Right>` (or `<C-b>`/`<C-f>`) move the query caret, `<Home>`/`<End>` (or `<C-a>`/`<C-e>`) jump, `<BS>`/`<Del>`/`<C-w>` edit, `<C-d>`/`<C-u>` page, mouse click/double-click/wheel. `grep` and `symbols` are live: each keystroke re-queries (debounced), and the preview jumps to the match.

Bindings are data, not code. Override any of them (in `browse`, `menu`, `sources`, or `prompt`) via `setup`, e.g. `require("loupe").setup({ mappings = { browse = { ["<CR>"] = "split" } } })`; set a value to `false` to unbind. See `lua/loupe/config.lua` for the full action set.

## Health & tests

`:checkhealth loupe` reports external tools (`fd`/`rg`/`git`), the resolved enumeration backends and matcher, and the resolved project root.

Pure unit tests (no plugins) run headlessly and in CI:

```sh
nvim --headless -u tests/minimal_init.lua -l tests/run.lua
```

# License

[MIT](./LICENSE)
