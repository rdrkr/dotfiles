-- Plugin: saghen/blink.cmp
-- Installed via store.nvim

return {
    "saghen/blink.cmp",
    dependencies = {
        "folke/noice.nvim",
        "rafamadriz/friendly-snippets",
    },
    event = "VeryLazy",
    opts = {
        cmdline = {
            keymap = {
                ["<Tab>"] = { "show", "accept" },
            },
            completion = {
                ghost_text = { enabled = true },
                menu = { auto_show = true },
            },
        },
    },
}
