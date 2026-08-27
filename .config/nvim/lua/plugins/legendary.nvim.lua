-- Plugin: mrjones2014/legendary.nvim
-- Installed via store.nvim

return {
    "mrjones2014/legendary.nvim",
    dependencies = {
        "kkharji/sqlite.lua",
    },
    event = "VeryLazy",
    keys = {
        { "<C-S-p>", "<cmd>Legendary<cr>", desc = "Open Command Palette" },
        { "<leader>p", "<cmd>Legendary<cr>", desc = "Open Command Palette" },
    },
    opts = {
        which_key = { auto_register = true },
    },
}
