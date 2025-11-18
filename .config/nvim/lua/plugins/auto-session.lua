-- Plugin: rmagatti/auto-session
-- Installed via store.nvim

return {
    "rmagatti/auto-session",
    lazy = false,
    ---enables autocomplete for opts
    ---@module "auto-session"
    ---@type AutoSession.Config
    opts = {
        suppressed_dirs = {
            "~/",
            "~/Projects",
            "~/Downloads",
            "/"
        }
        -- log_level = 'debug',
    }
}