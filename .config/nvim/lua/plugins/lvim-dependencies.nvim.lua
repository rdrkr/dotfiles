return {
    "lvim-tech/lvim-dependencies",
    dependencies = {
        "nvim-lua/plenary.nvim",
    },
    config = function()
        require("lvim-dependencies").setup({
            package = { enabled = false },
            crates = { enabled = false },
            pubspec = { enabled = false },
            composer = { enabled = false },
            go = { enabled = true },
            notify = {
                enabled = false,
                title = "LvimDeps",
                timeout = 5000,
            },
        })
    end,
}
