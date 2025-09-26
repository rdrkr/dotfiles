-- Plugin: s1n7ax/nvim-window-picker
-- Installed via store.nvim

return {
    "s1n7ax/nvim-window-picker",
    name = "window-picker",
    event = "VeryLazy",
    version = "2.*",
    config = function()
        require "window-picker".setup(

        )
    end
}