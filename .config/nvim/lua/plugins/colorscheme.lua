--- Colorscheme: Gruvbox Material, dark, medium background, "material" foreground palette.
--- Matches the Stylus browser themes and the lazygit theme in this dotfiles repo.
return {
    {
        --- sainnhe/gruvbox-material is configured through vim.g globals, which must be set
        --- before the colorscheme is loaded, hence `init` rather than `opts`.
        "sainnhe/gruvbox-material",
        lazy = false,
        priority = 1000,
        init = function()
            vim.o.background = "dark"
            vim.g.gruvbox_material_background = "medium"
            vim.g.gruvbox_material_foreground = "material"
            -- keep the terminal background showing through, as the previous setup did
            vim.g.gruvbox_material_transparent_background = 1
            vim.g.gruvbox_material_float_style = "dim"
            vim.g.gruvbox_material_enable_bold = 1
            vim.g.gruvbox_material_enable_italic = 1
            vim.g.gruvbox_material_diagnostic_virtual_text = "colored"
            vim.g.gruvbox_material_better_performance = 1
        end,
    },
    {
        --- Tell LazyVim to use it as the default colorscheme.
        "LazyVim/LazyVim",
        opts = {
            colorscheme = "gruvbox-material",
        },
    },
}
