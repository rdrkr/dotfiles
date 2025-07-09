return {
    -- add gruvbox
    {
        "ellisonleao/gruvbox.nvim",
        opts = {
            transparent_mode = true,
            styles = {
                sidebars = "transparent",
                floats = "transparent",
            },
        },
    },

    -- Configure LazyVim to load gruvbox
    {
        "LazyVim/LazyVim",
        opts = {
            colorscheme = "gruvbox",
            --"tokyonight",
            -- "gruvbox",
        },
    },
}
