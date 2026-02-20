-- Plugin: iamcco/markdown-preview.nvim
-- Added by store.nvim on 2026-02-20 11:55:18
return {
    "iamcco/markdown-preview.nvim",
    build = function()
        vim.fn["mkdp#util#install"]()
    end,
    event = "VeryLazy",
}
