-- Plugin: folke/snacks.nvim
-- Installed via store.nvim

return {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
        image = {
            -- your image configuration comes here
            -- or leave it empty to use the default settings
            -- refer to the configuration section below
        },
    },
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
