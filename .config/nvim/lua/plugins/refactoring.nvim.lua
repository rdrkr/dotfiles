return {
    "ThePrimeagen/refactoring.nvim",
    dependencies = {
        "lewis6991/async.nvim",
        "nvim-telescope/telescope.nvim", -- force telescope to be available first
    },
    config = function(_, opts)
        require("refactoring").setup(opts)
        pcall(require("telescope").load_extension, "refactoring")
    end,
}
