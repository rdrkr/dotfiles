-- Plugin: vuki656/package-info.nvim
-- Installed via store.nvim

return {
    "vuki656/package-info.nvim",
    dependencies = { "MunifTanjim/nui.nvim" },
    event = "VeryLazy",
    ft = { "json" }, -- only load for json files
    keys = {
        {
            "<leader>ns",
            function()
                require("package-info").show()
            end,
            silent = true,
            noremap = true,
            desc = "Show dependency versions",
            ft = "json",
        },
        {
            "<leader>nc",
            function()
                require("package-info").hide()
            end,
            silent = true,
            noremap = true,
            desc = "Hide dependency versions",
            ft = "json",
        },
        {
            "<leader>nt",
            function()
                require("package-info").toggle()
            end,
            silent = true,
            noremap = true,
            desc = "Toggle dependency versions",
            ft = "json",
        },
        {
            "<leader>nu",
            function()
                require("package-info").update()
            end,
            silent = true,
            noremap = true,
            desc = "Update dependency version",
            ft = "json",
        },
        {
            "<leader>nd",
            function()
                require("package-info").delete()
            end,
            silent = true,
            noremap = true,
            desc = "Delete dependency",
            ft = "json",
        },
        {
            "<leader>ni",
            function()
                require("package-info").install()
            end,
            silent = true,
            noremap = true,
            desc = "Install dependency",
            ft = "json",
        },
        {
            "<leader>np",
            function()
                require("package-info").change_version()
            end,
            silent = true,
            noremap = true,
            desc = "Change dependency version",
            ft = "json",
        },
    },
    config = function()
        require("package-info").setup()
    end,
}
