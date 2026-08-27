local is_mac = vim.fn.has("mac") == 1

local sources = { "filesystem", "buffers", "git_status" }
if is_mac then
    table.insert(sources, "apple-notes")
end

return {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "MunifTanjim/nui.nvim",
        "nvim-tree/nvim-web-devicons",
    },
    lazy = false,
    opts = vim.tbl_deep_extend("force", {
        sources = sources,
        filesystem = {
            filtered_items = {
                visible = true,
                hide_dotfiles = false,
                hide_gitignored = false,
            },
        },
    }, is_mac and {
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
    } or {}),
}
