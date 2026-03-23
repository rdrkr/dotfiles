return {
    "rdrkr/apple-notes.nvim",
    dependencies = {
        "nvim-telescope/telescope.nvim", -- optional: for note picker
        "nvim-neo-tree/neo-tree.nvim", -- optional: for tree sidebar
    },
    keys = {
        { "<leader>anf", "<cmd>AppleNotes<CR>", desc = "Find Apple Note" },
        { "<leader>ans", "<cmd>AppleNotesSearch<CR>", desc = "Search Apple Notes" },
        { "<leader>ann", "<cmd>AppleNotesNew<CR>", desc = "New Apple Note" },
        { "<leader>ant", "<cmd>AppleNotesTree<CR>", desc = "Toggle Apple Notes tree" },
    },
    event = "VeryLazy",
    opts = {},
}
