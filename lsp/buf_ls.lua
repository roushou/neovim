--- buf (protobuf) LSP configuration for |vim.lsp.config()|.
--- Server: `buf lsp serve` from the Buf CLI (https://buf.build/blog/protobuf-lsp).
return {
	cmd = { "buf", "lsp", "serve" },
	filetypes = { "proto" },
	root_markers = { "buf.yaml", "buf.work.yaml", ".git" },
}
