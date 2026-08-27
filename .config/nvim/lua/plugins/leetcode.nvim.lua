-- Plugin: kawre/leetcode.nvim
-- Installed via store.nvim

return {
    "kawre/leetcode.nvim",
    build = ":TSUpdate html", -- if you have `nvim-treesitter` installed
    lazy = false,
    dependencies = {
        -- include a picker of your choice, see picker section for more details
        "nvim-lua/plenary.nvim",
        "MunifTanjim/nui.nvim",
        "nvim-telescope/telescope.nvim",
        "nvim-treesitter/nvim-treesitter",
        "nvim-tree/nvim-web-devicons",
    },
    opts = {
        lang = "kotlin",
        image_support = true,
    },
    keys = {
        { "<leader>ll", "<cmd>Leet list<CR>", desc = "Leetcode List" },
        { "<leader>lr", "<cmd>Leet run<CR>", desc = "Leetcode Run" },
        { "<leader>ls", "<cmd>Leet submit<CR>", desc = "Leetcode Submit" },
        { "<leader>lo", "<cmd>Leet open<CR>", desc = "Leetcode Open" },
        { "<leader>lc", "<cmd>Leet console<CR>", desc = "Leetcode Console" },
        { "<leader>li", "<cmd>Leet info<CR>", desc = "Leetcode Info" },
        { "<leader>lt", "<cmd>Leet tabs<CR>", desc = "Leetcode Tabs" },
        { "<leader>le", "<cmd>Leet reset<CR>", desc = "Leetcode Reset" },
    },
    config = function(_, opts)
        require("leetcode").setup(opts)

        vim.api.nvim_create_autocmd("BufEnter", {
            pattern = vim.fn.expand("~") .. "/.local/share/nvim/leetcode/*",
            callback = function(ev)
                local bufnr = ev.buf

                -- Stop all LSP clients on this buffer
                vim.lsp.stop_client(vim.lsp.get_clients({ bufnr = bufnr }))

                -- Disable blink.cmp
                vim.b[bufnr].completion = false

                -- Disable Copilot
                vim.b[bufnr].copilot_enabled = false

                -- Disable diagnostics
                vim.diagnostic.enable(false, { bufnr = bufnr })
            end,
        })
    end,
}

