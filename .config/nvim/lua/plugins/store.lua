return {
    "alex-popov-tech/store.nvim",
    dependencies = {
        { "OXY2DEV/markview.nvim", opts = {} },
        { "3rd/image.nvim", opts = { integrations = { markdown = { enabled = false } } } },
    },
    opts = {
        layout = "tab", -- recommended when using image preview
    },
    cmd = "Store",
}
