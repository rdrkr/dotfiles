-- Plugin: neovim/nvim-lspconfig
-- Installed via store.nvim

return {
    "neovim/nvim-lspconfig",
    event = "VeryLazy",
    opts = {
        servers = {
            lua_ls = {
                mason = false,
            },
        },
    },
}
