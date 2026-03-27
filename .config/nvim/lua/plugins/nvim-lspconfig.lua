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
            kotlin_ls = {
                init_options = {
                    storagePath = vim.fn.stdpath("data") .. "/kotlin_ls",
                },
            },
        },
    },
}
