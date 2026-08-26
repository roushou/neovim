# Neovim

My personal Neovim configuration — built-in plugin management, declarative LSP setup, and a few hand-rolled replacements (tabline, statusline, picker, formatter).

<img width="1920" height="1170" alt="Editor with Kanagawa colorscheme showing a Rust file with custom statusline and buffer tabline" src="https://github.com/user-attachments/assets/25e34511-4c41-41bd-96cd-e6eb477e057e" />

**Lazygit**

<img width="1920" height="1170" alt="Lazygit floating terminal inside Neovim" src="https://github.com/user-attachments/assets/bf47d49c-e568-4a36-99b8-8e442f6c8afa" />

**Custom LSP info**

<img width="1920" height="1170" alt="Custom :LspInfo overview window listing attached LSP clients" src="https://github.com/user-attachments/assets/9c7394cc-cd55-4c97-8ac3-3a7e31d0b725" />

## Requirements

- Neovim **≥ 0.12** (`vim.pack`, `vim.lsp.config`, `lsp/` config dir)
- A [Nerd Font](https://www.nerdfonts.com/) for file icons and glyphs
- External tools: `git`, `lazygit`, `rg` (ripgrep)

LSP servers are **not** bundled — install the ones you need (e.g. `lua-language-server`, `gopls`, `basedpyright-langserver`) and make sure they're on your `$PATH`.

## Setup

```sh
git clone https://github.com/roushou/neovim.git ~/.config/nvim
nvim
```

Plugins are declared in [`init.lua`](./init.lua) via the built-in `vim.pack.add()` and pinned in [`nvim-pack-lock.json`](./nvim-pack-lock.json); run `:vim.pack.update()` to update.

## Layout

```
init.lua            entry point: plugins, colorscheme, textobjects
nvim-pack-lock.json pinned plugin revisions
after/plugin/       per-plugin configuration (blink, gitsigns, neo-tree, …)
lua/
├── keymaps.lua     global keymaps
├── settings.lua    options
├── util.lua        small helpers
├── keyd.lua        keymap-reveal helper
├── tabline.lua     custom buffer tabline (bufferline.nvim replacement)
├── format.lua      format-on-save via external binaries (conform.nvim replacement)
├── lsp/            LSP machinery: handlers, keys, :LspInfo UI, loader
plugins/            treesitter setup (parsers, textobjects)
lsp/                declarative server configs — one file per LSP
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
| `<C-p>`       | Pick file                 |
| `<leader>fw`  | Live grep                 |
| `<C-n>`       | Toggle file explorer      |
| `H` / `L`     | Previous / next buffer    |
| `<leader>x`   | Close buffer              |
| `<leader>li`  | LSP info                  |
| `<leader>ss`  | LSP symbols (document)    |
| `<leader>sw`  | LSP workspace symbols     |
| `<C-h/j/k/l>` | Navigate windows          |

# License

[MIT](./LICENSE)
