vim.lsp.enable('gopls')

vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())

package.path = package.path .. ";/home/jordo/.config/nvim/pack/nvim/start/nvim-lspconfig/lsp/?.lua"
local gopls_config = require('gopls')

require'cmp'.setup {
  sources = {
    { name = 'nvim_lsp' }
  }
}

-- The nvim-cmp almost supports LSP's capabilities so You should advertise it to LSP servers..
local capabilities = require('cmp_nvim_lsp').default_capabilities()

gopls_config = vim.tbl_extend('force', gopls_config, { capabilities = capabilities })

vim.lsp.config.gopls = gopls_config
