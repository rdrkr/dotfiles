-- Plugin: nvim-treesitter/nvim-treesitter
-- Installed via store.nvim

return {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    build = ":TSUpdate",
    opts = {
        ensure_installed = {
            "requirements", -- for py-requirements.nvim
            "toml", -- already installed, keep it
            "markdown",
            "markdown_inline",
            "vimdoc",
        },
    },
}
