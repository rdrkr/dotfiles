return {
    "rdrkr/apple-notes.nvim",
    cond = vim.fn.has("mac") == 1,
    dependencies = {
        "nvim-telescope/telescope.nvim",
        "nvim-neo-tree/neo-tree.nvim",
    },
    keys = {
        { "<leader>anf", "<cmd>AppleNotes<CR>", desc = "Find Apple Note" },
        { "<leader>ann", "<cmd>AppleNotesNew<CR>", desc = "New Apple Note" },
        { "<leader>ant", "<cmd>AppleNotesTree<CR>", desc = "Toggle Apple Notes tree" },
    },
    event = "VeryLazy",
    opts = {},
}
