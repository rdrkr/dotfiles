-- Plugin: MeanderingProgrammer/py-requirements.nvim
-- Installed via store.nvim

return {
    "MeanderingProgrammer/py-requirements.nvim",
    dependencies = {
        "nvim-treesitter/nvim-treesitter",
    },
    ft = { "requirements", "toml" },
    config = function()
        require("py-requirements").setup({
            index_url = "https://pypi.org/simple/",
            extra_index_url = nil,
            file_patterns = { ".*requirements.*.txt", ".*pyproject.*.toml" },
            diagnostic_opts = { padding = 5 },
            float_opts = { border = "rounded" },
            filter = {
                final_release = true,
                yanked = true,
            },
            enable_lsp = true,
        })

        vim.api.nvim_create_autocmd("BufEnter", {
            pattern = { "requirements*.txt", "*.toml" },
            callback = function()
                local opts = { silent = true, noremap = true, buffer = true }
                vim.keymap.set(
                    "n",
                    "<leader>ns",
                    require("py-requirements").show_description,
                    vim.tbl_extend("force", opts, { desc = "Show package description" })
                )
                vim.keymap.set(
                    "n",
                    "<leader>nu",
                    require("py-requirements").upgrade,
                    vim.tbl_extend("force", opts, { desc = "Upgrade package to latest version" })
                )
                vim.keymap.set(
                    "n",
                    "<leader>nU",
                    require("py-requirements").upgrade_all,
                    vim.tbl_extend("force", opts, { desc = "Upgrade all packages to latest version" })
                )
            end,
        })
    end,
}
