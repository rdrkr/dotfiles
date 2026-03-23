-- Plugin: nvim-neo-tree/neo-tree.nvim
-- Installed via store.nvim

return {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "MunifTanjim/nui.nvim",
        "nvim-tree/nvim-web-devicons", -- optional, but recommended
    },
    lazy = false, -- neo-tree will lazily load itself
    opts = {
        sources = {
            "filesystem",
            "buffers",
            "git_status",
            "apple-notes",
        },
        filesystem = {
            filtered_items = {
                visible = true,
                hide_dotfiles = false,
                hide_gitignored = false,
            },
        },
        ["apple-notes"] = {
            window = {
                mappings = {
                    ["o"] = "open",
                    ["a"] = "add",
                    ["A"] = "add_directory",
                    ["d"] = "delete",
                    ["r"] = "rename",
                    ["m"] = "move",
                    ["R"] = "refresh",
                },
            },
        },
    },
}
