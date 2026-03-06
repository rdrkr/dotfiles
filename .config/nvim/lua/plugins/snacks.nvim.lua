-- Plugin: folke/snacks.nvim
-- Installed via store.nvim

return {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    keys = {
        {
            "<leader>lg",
            function()
                Snacks.lazygit()
            end,
            desc = "Open Lazygit floating window",
        },
    },
}
